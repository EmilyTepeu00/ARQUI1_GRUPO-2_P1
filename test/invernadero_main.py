import random
import time
import json
import csv
import os
import threading
from datetime import datetime
from paho.mqtt import client as mqtt_client
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure

# ─── MODO DE OPERACION ────────────────────────────────────────
MODO_SIMULACION = True   # True = datos simulados | False = GPIO real

# ─── CONFIGURACION MQTT ───────────────────────────────────────
BROKER    = "broker.emqx.io"
PORT      = 1883
CLIENT_ID = f"InvernaderoG2_ARQUI1-pi-{random.randint(0, 9999)}"
USERNAME  = None
PASSWORD  = None

# ─── CONFIGURACION MONGODB ────────────────────────────────────
MONGO_URI = (
    "mongodb+srv://Invernadero_user:Invernadero2026"
    "@invernadero-cluster.gdzxx9p.mongodb.net/"
    "?appName=Invernadero-cluster"
)
MONGO_DB_NAME    = "invernadero_g2"

# Colecciones
COL_SENSOR_READINGS = "sensor_readings"
COL_EVENTS          = "events"
COL_COMMANDS        = "commands"
COL_SYSTEM_STATUS   = "system_status"
COL_ACTUATOR_LOGS   = "actuator_logs"
COL_ARM64_RESULTS   = "arm64_results"

# ─── ARCHIVO CSV ──────────────────────────────────────────────
CSV_FILE    = "lecturas.csv"
CSV_HEADERS = ["ID", "TEMP", "HUM_AIRE", "HUM_SUELO_1",
               "HUM_SUELO_2", "LUZ", "GAS", "RIEGO_1", "RIEGO_2"]
MAX_CSV_ROWS = 30   # El proyecto requiere exactamente 30 registros

# ─── TOPICS SENSORES ──────────────────────────────────────────
TOPIC_TEMPERATURA      = "InvernaderoG2_ARQUI1/sensores/temperatura"
TOPIC_HUMEDAD_AMBIENTE = "InvernaderoG2_ARQUI1/sensores/humedad_ambiente"
TOPIC_HUMEDAD_SUELO_1  = "InvernaderoG2_ARQUI1/sensores/humedad_suelo_area1"
TOPIC_HUMEDAD_SUELO_2  = "InvernaderoG2_ARQUI1/sensores/humedad_suelo_area2"
TOPIC_LUZ              = "InvernaderoG2_ARQUI1/sensores/luz"
TOPIC_GAS              = "InvernaderoG2_ARQUI1/sensores/gas"

# ─── TOPICS ACTUADORES ────────────────────────────────────────
TOPIC_RIEGO            = "InvernaderoG2_ARQUI1/actuadores/riego"
TOPIC_RIEGO_AREA1      = "InvernaderoG2_ARQUI1/actuadores/riego_area1"
TOPIC_RIEGO_AREA2      = "InvernaderoG2_ARQUI1/actuadores/riego_area2"
TOPIC_VENTILADOR       = "InvernaderoG2_ARQUI1/actuadores/ventilador"
TOPIC_LUCES            = "InvernaderoG2_ARQUI1/actuadores/luces"
TOPIC_ALARMA           = "InvernaderoG2_ARQUI1/actuadores/alarma"

# ─── TOPICS ESTADO Y CONTROL ──────────────────────────────────
TOPIC_ESTADO_GLOBAL    = "InvernaderoG2_ARQUI1/estado/global"
TOPIC_CONTROL_REMOTO   = "InvernaderoG2_ARQUI1/control/remoto"
TOPIC_CONTROL_MANUAL   = "InvernaderoG2_ARQUI1/control/manual"

# ─── ESTADO INTERNO DEL SISTEMA ───────────────────────────────
estado_sistema = {
    "global":       "NORMAL",     # NORMAL / ADVERTENCIA / RIEGO_ACTIVO / MODO_MANUAL / EMERGENCIA
    "riego":        "RIEGO_OFF",  # RIEGO_OFF / RIEGO_AREA_1 / RIEGO_AREA_2 / RIEGO_MANUAL / BLOQUEADO_POR_SATURACION
    "ventilador":   "VENTILACION_OFF",
    "luces":        "OFF",
    "alarma":       "OFF",
    "modo":         "AUTOMATICO", # AUTOMATICO / MANUAL
    "gas":          "GAS_NORMAL",
}

# ─── UMBRALES ─────────────────────────────────────────────────
UMBRAL_TEMP_ALTA      = 32.0   # °C  — activa ventilador
UMBRAL_HUMEDAD_BAJA   = 40     # %   — suelo SECO
UMBRAL_HUMEDAD_NORMAL = 70     # %   — suelo NORMAL (arriba = SATURADO)
UMBRAL_LUZ_BAJA       = 300    # ADC — activa luces
UMBRAL_GAS_ADVERTENCIA = 150   # ADC
UMBRAL_GAS_EMERGENCIA  = 200   # ADC

# ─── VARIABLES GLOBALES DE CONEXION ───────────────────────────
mqtt_connected = False
cliente_mqtt   = None
cliente_mongo  = None
db_mongo       = None
csv_id_counter = 1          # Contador de filas del CSV
csv_lock       = threading.Lock()


# ══════════════════════════════════════════════════════════════
# SECCION 1: MONGODB
# ══════════════════════════════════════════════════════════════

def iniciar_mongo():
    """Conecta a MongoDB Atlas y retorna True si tuvo éxito."""
    global cliente_mongo, db_mongo
    try:
        cliente_mongo = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
        cliente_mongo.admin.command("ping")   # Verifica conexión real
        db_mongo = cliente_mongo[MONGO_DB_NAME]
        print(f"[MONGO] Conectado a '{MONGO_DB_NAME}' en Atlas ✓")
        return True
    except ConnectionFailure as e:
        print(f"[MONGO] ERROR de conexión: {e}")
        return False
    except Exception as e:
        print(f"[MONGO] ERROR inesperado: {e}")
        return False


def guardar_en_mongo(coleccion: str, documento: dict):
    """Inserta un documento en la colección indicada."""
    if db_mongo is None:
        print(f"[MONGO] Sin conexión — no se guardó en '{coleccion}'")
        return
    try:
        resultado = db_mongo[coleccion].insert_one(documento)
        print(f"[MONGO] OK → '{coleccion}' | _id: {resultado.inserted_id}")
    except Exception as e:
        print(f"[MONGO] ERROR al insertar en '{coleccion}': {e}")


def actualizar_estado_global_mongo():
    """Actualiza (upsert) el documento de estado global en system_status."""
    if db_mongo is None:
        return
    try:
        db_mongo[COL_SYSTEM_STATUS].update_one(
            {"_id": "estado_actual"},
            {"$set": {
                **estado_sistema,
                "timestamp": datetime.now().isoformat()
            }},
            upsert=True
        )
    except Exception as e:
        print(f"[MONGO] ERROR al actualizar estado global: {e}")


# ══════════════════════════════════════════════════════════════
# SECCION 2: CSV
# ══════════════════════════════════════════════════════════════

def inicializar_csv():
    """Crea el archivo CSV con encabezados si no existe."""
    global csv_id_counter
    if not os.path.exists(CSV_FILE):
        with open(CSV_FILE, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(CSV_HEADERS)
        csv_id_counter = 1
        print(f"[CSV] Archivo '{CSV_FILE}' creado con encabezados.")
    else:
        # Retomar el contador desde las filas existentes
        with open(CSV_FILE, "r") as f:
            lineas = f.readlines()
        filas_datos = len(lineas) - 1  # Excluye encabezado
        csv_id_counter = max(1, filas_datos + 1)
        print(f"[CSV] Archivo existente — {filas_datos} registros previos. "
              f"Continuando desde ID {csv_id_counter}.")


def agregar_fila_csv(temp, hum_aire, hum_suelo1, hum_suelo2,
                     luz, gas, riego1, riego2):
    """
    Agrega una fila al CSV.
    Solo escribe si aún no se alcanzaron los 30 registros requeridos.
    Retorna True si la fila fue escrita.
    """
    global csv_id_counter
    with csv_lock:
        if csv_id_counter > MAX_CSV_ROWS:
            return False   # Ya tenemos los 30 registros

        fila = [
            csv_id_counter,
            round(temp, 1),
            int(hum_aire),
            int(hum_suelo1),
            int(hum_suelo2),
            int(luz),
            int(gas),
            int(riego1),
            int(riego2),
        ]
        with open(CSV_FILE, "a", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(fila)

        print(f"[CSV] Fila {csv_id_counter}/{MAX_CSV_ROWS} → {fila}")
        csv_id_counter += 1

        if csv_id_counter > MAX_CSV_ROWS:
            print(f"[CSV] ¡Archivo completo! {MAX_CSV_ROWS} registros listos para ARM64.")

        return True


# ══════════════════════════════════════════════════════════════
# SECCION 3: SENSORES SIMULADOS
# (Reemplazar con lectura real de GPIO cuando tengas la Raspberry)
# ══════════════════════════════════════════════════════════════

def leer_temperatura():
    """
    SIMULADO: DHT22 → temperatura entre 24 y 36 °C
    REAL: import Adafruit_DHT; _, temp = Adafruit_DHT.read_retry(Adafruit_DHT.DHT22, PIN_DHT)
    """
    return round(random.uniform(24.0, 36.0), 1)


def leer_humedad_ambiente():
    """
    SIMULADO: DHT22 → humedad ambiental entre 40 y 90 %
    REAL: hum, _ = Adafruit_DHT.read_retry(Adafruit_DHT.DHT22, PIN_DHT)
    """
    return round(random.uniform(40.0, 90.0), 1)


def leer_humedad_suelo(area: int):
    """
    SIMULADO: Sensor capacitivo → valor 0-100 (porcentaje de humedad)
    REAL (ADC en Raspberry): leer_adc(canal_area) y mapear a 0-100
    area=1 → Area de cultivo 1, area=2 → Area de cultivo 2
    """
    return random.randint(20, 95)


def clasificar_suelo(valor: int) -> str:
    """Clasifica la humedad del suelo según umbrales del proyecto."""
    if valor < UMBRAL_HUMEDAD_BAJA:
        return "SECO"
    elif valor <= UMBRAL_HUMEDAD_NORMAL:
        return "NORMAL"
    else:
        return "SATURADO"


def leer_luz():
    """
    SIMULADO: LDR → valor ADC entre 50 y 900
    REAL: leer_adc(canal_ldr)  (a través de MCP3008 u otro ADC externo)
    """
    return random.randint(50, 900)


def leer_gas():
    """
    SIMULADO: MQ-2/MQ-135 → valor ADC entre 80 y 280
    REAL: leer_adc(canal_gas)
    """
    return random.randint(80, 280)


# ══════════════════════════════════════════════════════════════
# SECCION 4: LOGICA DE CONTROL AUTOMATICO
# ══════════════════════════════════════════════════════════════

def evaluar_estado_global(temp, hum_suelo1, hum_suelo2,
                           estado_gas, riego_activo):
    """Determina el estado global según reglas del proyecto."""
    if estado_gas == "GAS_EMERGENCIA":
        return "EMERGENCIA"
    if riego_activo:
        return "RIEGO_ACTIVO"
    if estado_sistema["modo"] == "MANUAL":
        return "MODO_MANUAL"
    if (temp > UMBRAL_TEMP_ALTA or
            hum_suelo1 < UMBRAL_HUMEDAD_BAJA or
            hum_suelo2 < UMBRAL_HUMEDAD_BAJA):
        return "ADVERTENCIA"
    return "NORMAL"


def decidir_riego(hum_suelo1, hum_suelo2):
    """Decide qué área regar (o bloquear) según humedad del suelo."""
    if estado_sistema["modo"] == "MANUAL":
        return  # En modo manual no hay riego automático

    estado1 = clasificar_suelo(hum_suelo1)
    estado2 = clasificar_suelo(hum_suelo2)

    if estado1 == "SATURADO" or estado2 == "SATURADO":
        estado_sistema["riego"] = "BLOQUEADO_POR_SATURACION"
        return

    if estado1 == "SECO" and estado2 == "SECO":
        # Prioriza área 1; el loop siguiente activará área 2
        estado_sistema["riego"] = "RIEGO_AREA_1"
    elif estado1 == "SECO":
        estado_sistema["riego"] = "RIEGO_AREA_1"
    elif estado2 == "SECO":
        estado_sistema["riego"] = "RIEGO_AREA_2"
    else:
        estado_sistema["riego"] = "RIEGO_OFF"


def decidir_ventilador(temp, estado_gas):
    """Activa ventilador si hay temperatura alta o gas peligroso."""
    if estado_gas in ("GAS_ADVERTENCIA", "GAS_EMERGENCIA"):
        estado_sistema["ventilador"] = "VENTILACION_EMERGENCIA"
    elif temp > UMBRAL_TEMP_ALTA:
        estado_sistema["ventilador"] = "VENTILACION_ON"
    elif estado_sistema["modo"] != "MANUAL":
        estado_sistema["ventilador"] = "VENTILACION_OFF"


def decidir_luces(luz):
    """Activa luces cuando hay poca luz ambiental (modo automático)."""
    if estado_sistema["modo"] == "MANUAL":
        return
    if luz < UMBRAL_LUZ_BAJA:
        estado_sistema["luces"] = "ON"
    else:
        estado_sistema["luces"] = "OFF"


def decidir_alarma(estado_gas):
    """Activa la alarma en caso de emergencia por gas."""
    if estado_gas == "GAS_EMERGENCIA":
        estado_sistema["alarma"] = "ON"
    # La alarma solo se apaga manualmente (Botón 4 o comando remoto)


# ══════════════════════════════════════════════════════════════
# SECCION 5: MQTT — CALLBACKS
# ══════════════════════════════════════════════════════════════

def on_connect(client, userdata, flags, rc):
    global mqtt_connected
    if rc == 0:
        print("[MQTT] Conectado al broker ✓")
        mqtt_connected = True
        client.subscribe("InvernaderoG2_ARQUI1/#")
        print("[MQTT] Suscrito a InvernaderoG2_ARQUI1/#")
    else:
        print(f"[MQTT] Fallo de conexión, código: {rc}")
        mqtt_connected = False


def on_disconnect(client, userdata, rc):
    global mqtt_connected
    mqtt_connected = False
    if rc != 0:
        print("[MQTT] Desconexión inesperada. Intentando reconectar...")


def on_message(client, userdata, msg):
    """
    Recibe CUALQUIER mensaje del topic InvernaderoG2_ARQUI1/#
    — Comandos de control → se procesan
    — Lecturas propias publicadas → solo se muestran en terminal
    """
    try:
        payload = json.loads(msg.payload.decode())
        topic   = msg.topic

        # ── Comandos de control (remoto o manual) ─────────────
        if topic in (TOPIC_CONTROL_REMOTO, TOPIC_CONTROL_MANUAL):
            origen = "REMOTO" if topic == TOPIC_CONTROL_REMOTO else "MANUAL"
            print(f"\n[MQTT ← {origen}] Comando recibido en [{topic}]: {payload}")
            procesar_comando(payload, origen)

        # ── Echo de lecturas propias (para verificar que llegan) ─
        else:
            print(f"[MQTT ←] [{topic}] {payload}")

    except json.JSONDecodeError:
        raw = msg.payload.decode()
        print(f"[MQTT ←] [{msg.topic}] (texto plano): {raw}")
    except Exception as e:
        print(f"[MQTT] Error procesando mensaje: {e}")


# ══════════════════════════════════════════════════════════════
# SECCION 6: MQTT — PROCESAR COMANDOS
# ══════════════════════════════════════════════════════════════

def procesar_comando(payload: dict, origen: str = "REMOTO"):
    """
    Procesa comandos recibidos via MQTT.
    Se ejecuta desde el callback on_message en hilo separado de paho.
    """
    accion = payload.get("accion", "").upper()
    valor  = payload.get("valor",  "").upper()
    ts     = datetime.now().isoformat()

    print(f"[CMD] Acción={accion} | Valor={valor} | Origen={origen}")

    # Registro en MongoDB
    doc_comando = {
        "accion":    accion,
        "valor":     valor,
        "origen":    origen,
        "timestamp": ts,
        "estado_previo": estado_sistema.copy()
    }

    # ── Acciones disponibles ───────────────────────────────────
    if accion == "RIEGO_AREA1":
        if valor == "ON":
            estado_sistema["riego"] = "RIEGO_AREA_1"
            _publicar(TOPIC_RIEGO_AREA1, {"estado": "ON", "timestamp": ts})
        else:
            estado_sistema["riego"] = "RIEGO_OFF"
            _publicar(TOPIC_RIEGO_AREA1, {"estado": "OFF", "timestamp": ts})
        print(f"[CMD] Riego Área 1 → {valor}")

    elif accion == "RIEGO_AREA2":
        if valor == "ON":
            estado_sistema["riego"] = "RIEGO_AREA_2"
            _publicar(TOPIC_RIEGO_AREA2, {"estado": "ON", "timestamp": ts})
        else:
            estado_sistema["riego"] = "RIEGO_OFF"
            _publicar(TOPIC_RIEGO_AREA2, {"estado": "OFF", "timestamp": ts})
        print(f"[CMD] Riego Área 2 → {valor}")

    elif accion == "VENTILADOR":
        if valor == "ON":
            estado_sistema["ventilador"] = "VENTILACION_MANUAL"
            estado_sistema["modo"]       = "MANUAL"
        else:
            estado_sistema["ventilador"] = "VENTILACION_OFF"
        _publicar(TOPIC_VENTILADOR, {"estado": valor, "timestamp": ts})
        print(f"[CMD] Ventilador → {valor}")

    elif accion == "LUCES":
        estado_sistema["luces"] = valor   # "ON" o "OFF"
        estado_sistema["modo"]  = "MANUAL"
        _publicar(TOPIC_LUCES, {"estado": valor, "timestamp": ts})
        print(f"[CMD] Luces → {valor}")

    elif accion == "ALARMA":
        if valor == "OFF":
            estado_sistema["alarma"] = "OFF"
            _publicar(TOPIC_ALARMA, {"estado": "OFF", "timestamp": ts})
        print(f"[CMD] Alarma silenciada")

    elif accion == "MODO":
        if valor in ("AUTOMATICO", "MANUAL"):
            estado_sistema["modo"] = valor
            print(f"[CMD] Modo cambiado → {valor}")
        else:
            print(f"[CMD] Modo desconocido: {valor}")

    elif accion == "RESET":
        estado_sistema["global"]     = "NORMAL"
        estado_sistema["alarma"]     = "OFF"
        estado_sistema["modo"]       = "AUTOMATICO"
        print("[CMD] Sistema restablecido a estado NORMAL automático")

    else:
        print(f"[CMD] Acción desconocida: {accion}")

    # Guardar comando en MongoDB
    doc_comando["estado_nuevo"] = estado_sistema.copy()
    guardar_en_mongo(COL_COMMANDS, doc_comando)
    actualizar_estado_global_mongo()


# ══════════════════════════════════════════════════════════════
# SECCION 7: MQTT — PUBLICAR
# ══════════════════════════════════════════════════════════════

def _publicar(topic: str, datos: dict):
    global cliente_mqtt, mqtt_connected
    if not mqtt_connected or cliente_mqtt is None:
        print(f"[MQTT] Sin conexión — no se publicó en {topic}")
        return
    mensaje   = json.dumps(datos)
    resultado = cliente_mqtt.publish(topic, mensaje, qos=0)
    if resultado[0] == 0:
        print(f"[MQTT →] {topic}: {mensaje}")
    else:
        print(f"[MQTT] ERROR al publicar en {topic}")


def publicar_temperatura(valor: float):
    _publicar(TOPIC_TEMPERATURA, {
        "valor":     valor,
        "unidad":    "C",
        "timestamp": datetime.now().isoformat(),
        "origen":    "DHT22" if not MODO_SIMULACION else "SIMULADO"
    })


def publicar_humedad_ambiente(valor: float):
    _publicar(TOPIC_HUMEDAD_AMBIENTE, {
        "valor":     valor,
        "unidad":    "%",
        "timestamp": datetime.now().isoformat(),
        "origen":    "DHT22" if not MODO_SIMULACION else "SIMULADO"
    })


def publicar_humedad_suelo(area: int, valor: int, estado: str):
    topic = TOPIC_HUMEDAD_SUELO_1 if area == 1 else TOPIC_HUMEDAD_SUELO_2
    _publicar(topic, {
        "valor":     valor,
        "estado":    estado,
        "area":      area,
        "timestamp": datetime.now().isoformat(),
        "origen":    f"sensor_suelo_area{area}" if not MODO_SIMULACION else "SIMULADO"
    })


def publicar_luz(valor: int):
    _publicar(TOPIC_LUZ, {
        "valor":     valor,
        "timestamp": datetime.now().isoformat(),
        "origen":    "LDR" if not MODO_SIMULACION else "SIMULADO"
    })


def publicar_gas(valor: int, estado: str):
    _publicar(TOPIC_GAS, {
        "valor":     valor,
        "estado":    estado,
        "timestamp": datetime.now().isoformat(),
        "origen":    "MQ2" if not MODO_SIMULACION else "SIMULADO"
    })


def publicar_actuadores():
    """Publica el estado actual de todos los actuadores."""
    ts = datetime.now().isoformat()
    _publicar(TOPIC_RIEGO,      {"estado": estado_sistema["riego"],      "timestamp": ts})
    _publicar(TOPIC_VENTILADOR, {"estado": estado_sistema["ventilador"], "timestamp": ts})
    _publicar(TOPIC_LUCES,      {"estado": estado_sistema["luces"],      "timestamp": ts})
    _publicar(TOPIC_ALARMA,     {"estado": estado_sistema["alarma"],     "timestamp": ts})
    _publicar(TOPIC_ESTADO_GLOBAL, {
        "estado":    estado_sistema["global"],
        "modo":      estado_sistema["modo"],
        "timestamp": ts
    })


# ══════════════════════════════════════════════════════════════
# SECCION 8: LOOP PRINCIPAL DE LECTURAS
# ══════════════════════════════════════════════════════════════

def ciclo_lectura():
    """
    Ejecuta un ciclo completo:
    1. Lee sensores (simulados o reales)
    2. Aplica lógica de control automático
    3. Publica por MQTT
    4. Guarda en MongoDB
    5. Agrega fila al CSV
    """
    ts = datetime.now().isoformat()

    # ── 1. Lectura de sensores ─────────────────────────────────
    temp       = leer_temperatura()
    hum_aire   = leer_humedad_ambiente()
    hum_suelo1 = leer_humedad_suelo(1)
    hum_suelo2 = leer_humedad_suelo(2)
    luz        = leer_luz()
    gas        = leer_gas()

    estado_suelo1 = clasificar_suelo(hum_suelo1)
    estado_suelo2 = clasificar_suelo(hum_suelo2)

    # Clasificar gas
    if gas >= UMBRAL_GAS_EMERGENCIA:
        estado_sistema["gas"] = "GAS_EMERGENCIA"
    elif gas >= UMBRAL_GAS_ADVERTENCIA:
        estado_sistema["gas"] = "GAS_ADVERTENCIA"
    else:
        estado_sistema["gas"] = "GAS_NORMAL"

    print(f"\n{'='*60}")
    print(f"[LECTURA] {ts}")
    print(f"  Temp: {temp}°C | Hum. Aire: {hum_aire}%")
    print(f"  Suelo1: {hum_suelo1}% ({estado_suelo1}) | "
          f"Suelo2: {hum_suelo2}% ({estado_suelo2})")
    print(f"  Luz: {luz} | Gas: {gas} ({estado_sistema['gas']})")
    print(f"  Modo: {estado_sistema['modo']}")

    # ── 2. Lógica de control ───────────────────────────────────
    if estado_sistema["modo"] == "AUTOMATICO":
        decidir_ventilador(temp, estado_sistema["gas"])
        decidir_luces(luz)
        decidir_riego(hum_suelo1, hum_suelo2)
        decidir_alarma(estado_sistema["gas"])

    riego_activo = estado_sistema["riego"] not in ("RIEGO_OFF", "BLOQUEADO_POR_SATURACION")
    estado_sistema["global"] = evaluar_estado_global(
        temp, hum_suelo1, hum_suelo2, estado_sistema["gas"], riego_activo
    )

    print(f"  Estado Global: {estado_sistema['global']} | "
          f"Riego: {estado_sistema['riego']} | "
          f"Ventilador: {estado_sistema['ventilador']}")
    print(f"  Luces: {estado_sistema['luces']} | "
          f"Alarma: {estado_sistema['alarma']}")

    # ── 3. Publicar por MQTT ───────────────────────────────────
    publicar_temperatura(temp)
    time.sleep(7)

    publicar_humedad_ambiente(hum_aire)
    time.sleep(7)

    publicar_humedad_suelo(1, hum_suelo1, estado_suelo1)
    time.sleep(7)

    publicar_humedad_suelo(2, hum_suelo2, estado_suelo2)
    time.sleep(7)

    publicar_luz(luz)
    time.sleep(7)

    publicar_gas(gas, estado_sistema["gas"])
    time.sleep(7)

    publicar_actuadores()

    # ── 4. Guardar en MongoDB ──────────────────────────────────
    doc_lectura = {
        "timestamp":   ts,
        "tipo":        "sensor_reading",
        "origen":      "SIMULADO" if MODO_SIMULACION else "DHT22/GPIO",
        "temperatura": {"valor": temp,       "unidad": "C"},
        "hum_aire":    {"valor": hum_aire,   "unidad": "%"},
        "hum_suelo_1": {"valor": hum_suelo1, "estado": estado_suelo1},
        "hum_suelo_2": {"valor": hum_suelo2, "estado": estado_suelo2},
        "luz":         {"valor": luz},
        "gas":         {"valor": gas,        "estado": estado_sistema["gas"]},
        "estado":      estado_sistema["global"],
    }
    guardar_en_mongo(COL_SENSOR_READINGS, doc_lectura)

    # Guardar estado de actuadores
    doc_actuadores = {
        "timestamp":  ts,
        "tipo":       "actuator_state",
        "riego":      estado_sistema["riego"],
        "ventilador": estado_sistema["ventilador"],
        "luces":      estado_sistema["luces"],
        "alarma":     estado_sistema["alarma"],
        "modo":       estado_sistema["modo"],
    }
    guardar_en_mongo(COL_ACTUATOR_LOGS, doc_actuadores)

    # Registrar evento si hay condición anormal
    if estado_sistema["global"] != "NORMAL":
        doc_evento = {
            "timestamp": ts,
            "tipo":      "event",
            "estado":    estado_sistema["global"],
            "gas":       estado_sistema["gas"],
            "riego":     estado_sistema["riego"],
            "temp":      temp,
            "origen":    "control_automatico",
        }
        guardar_en_mongo(COL_EVENTS, doc_evento)

    actualizar_estado_global_mongo()

    # ── 5. Agregar fila al CSV ─────────────────────────────────
    riego1_bin = 1 if estado_sistema["riego"] == "RIEGO_AREA_1" else 0
    riego2_bin = 1 if estado_sistema["riego"] == "RIEGO_AREA_2" else 0
    agregar_fila_csv(temp, hum_aire, hum_suelo1, hum_suelo2,
                     luz, gas, riego1_bin, riego2_bin)


# ══════════════════════════════════════════════════════════════
# SECCION 9: INICIAR / DETENER MQTT
# ══════════════════════════════════════════════════════════════

def iniciar_mqtt():
    global cliente_mqtt

    client = mqtt_client.Client(client_id=CLIENT_ID)
    cliente_mqtt = client

    client.on_connect    = on_connect
    client.on_disconnect = on_disconnect
    client.on_message    = on_message

    client.reconnect_delay_set(min_delay=1, max_delay=30)
    client.connect(BROKER, PORT, keepalive=60)
    client.loop_start()

    timeout = time.time() + 8
    while not mqtt_connected and time.time() < timeout:
        time.sleep(0.1)

    if mqtt_connected:
        print("[MQTT] Listo ✓")
    else:
        print("[MQTT] ADVERTENCIA: no se conectó en 8 segundos")

    return client


def detener_mqtt():
    global cliente_mqtt
    if cliente_mqtt:
        cliente_mqtt.disconnect()
        cliente_mqtt.loop_stop()
        print("[MQTT] Desconectado")


# ══════════════════════════════════════════════════════════════
# SECCION 10: MAIN
# ══════════════════════════════════════════════════════════════

def main():
    print("=" * 60)
    print("  INVERNADERO INTELIGENTE IoT — Grupo G2 — ARQUI1")
    print(f"  Modo: {'SIMULACIÓN' if MODO_SIMULACION else 'HARDWARE REAL'}")
    print("=" * 60)

    # 1. Conectar MongoDB
    mongo_ok = iniciar_mongo()
    if not mongo_ok:
        print("[ADVERTENCIA] Continuando sin MongoDB — los datos no se guardarán.")

    # 2. Inicializar CSV
    inicializar_csv()

    # 3. Conectar MQTT
    iniciar_mqtt()

    # 4. Loop principal — publica cada INTERVALO segundos
    INTERVALO = 15   # segundos entre lecturas (ajustar según necesidad)
    print(f"\n[MAIN] Iniciando ciclos de lectura cada {INTERVALO}s...")
    print("[MAIN] Presiona Ctrl+C para detener.\n")

    try:
        while True:
            ciclo_lectura()
            time.sleep(INTERVALO)
    except KeyboardInterrupt:
        print("\n[MAIN] Deteniendo sistema...")
    finally:
        detener_mqtt()
        if cliente_mongo:
            cliente_mongo.close()
            print("[MONGO] Conexión cerrada.")
        print("[MAIN] Sistema apagado correctamente.")


if __name__ == "__main__":
    main()
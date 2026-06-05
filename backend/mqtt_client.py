import json
import random
import time
from datetime import datetime
from paho.mqtt import client as mqtt_client

import config
import database as db
from state import estado_sistema, procesar_comando, aplicar_logica_automatica, clasificar_suelo, clasificar_gas

_cliente   = None
_conectado = False

# Acumula la ultima lectura recibida desde la rasp (modo raspberry)
_ultima_lectura = {}


def on_connect(client, userdata, flags, rc):
    global _conectado
    if rc == 0:
        print("[MQTT] Conectado al broker OK")
        _conectado = True
        client.subscribe(f"{config.MQTT_PREFIX}/#")
        print(f"[MQTT] Suscrito a {config.MQTT_PREFIX}/#")
    else:
        print(f"[MQTT] Fallo de conexion rc={rc}")
        _conectado = False


def on_disconnect(client, userdata, rc):
    global _conectado
    _conectado = False
    if rc != 0:
        print("[MQTT] Desconexion inesperada")


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode())
        topic   = msg.topic
        print(f"[MQTT RX] {topic}: {payload}")

        if topic in (config.TOPIC_CONTROL_REMOTO, config.TOPIC_CONTROL_MANUAL):
            origen = "REMOTO" if topic == config.TOPIC_CONTROL_REMOTO else "MANUAL"
            procesar_comando(payload, origen)
            return

        # En modo raspberry los sensores llegan por MQTT y los procesamos aqui
        if config.MODO == "raspberry":
            _procesar_lectura_rasp(topic, payload)

    except Exception as e:
        print(f"[MQTT] Error en mensaje: {e}")


def _procesar_lectura_rasp(topic, payload):
    """
    Recibe cada topic de sensor de la Raspberry Pi,
    acumula en _ultima_lectura y cuando tiene todos los datos
    aplica la logica de control y guarda en MongoDB.
    """
    global _ultima_lectura
    ts = payload.get("timestamp", datetime.now().isoformat())

    if topic == config.TOPIC_TEMPERATURA:
        _ultima_lectura["temperatura"] = payload.get("valor", 0)
        _ultima_lectura["ts"] = ts

    elif topic == config.TOPIC_HUMEDAD_AMBIENTE:
        _ultima_lectura["hum_aire"] = payload.get("valor", 0)

    elif topic == config.TOPIC_HUMEDAD_SUELO_1:
        _ultima_lectura["hum_suelo1"] = payload.get("valor", 0)

    elif topic == config.TOPIC_HUMEDAD_SUELO_2:
        _ultima_lectura["hum_suelo2"] = payload.get("valor", 0)

    elif topic == config.TOPIC_LUZ:
        _ultima_lectura["luz"] = payload.get("valor", 0)

    elif topic == config.TOPIC_GAS:
        _ultima_lectura["gas"] = payload.get("valor", 0)

    # Cuando tenemos los 6 sensores guardamos en Mongo
    campos = {"temperatura","hum_aire","hum_suelo1","hum_suelo2","luz","gas"}
    if campos.issubset(_ultima_lectura.keys()):
        _guardar_lectura_completa(_ultima_lectura.copy())
        _ultima_lectura = {}


def _guardar_lectura_completa(l):
    ts            = l.get("ts", datetime.now().isoformat())
    estado_suelo1 = clasificar_suelo(l["hum_suelo1"])
    estado_suelo2 = clasificar_suelo(l["hum_suelo2"])
    estado_gas    = clasificar_gas(l["gas"])

    lecturas = {
        "temperatura":   l["temperatura"],
        "hum_aire":      l["hum_aire"],
        "hum_suelo1":    l["hum_suelo1"],
        "hum_suelo2":    l["hum_suelo2"],
        "luz":           l["luz"],
        "gas":           l["gas"],
        "estado_suelo1": estado_suelo1,
        "estado_suelo2": estado_suelo2,
        "estado_gas":    estado_gas,
    }

    aplicar_logica_automatica(lecturas)
    from state import obtener_estado
    estado = obtener_estado()

    print(f"[RASP] Temp={l['temperatura']}C Suelo1={l['hum_suelo1']}% Gas={l['gas']}")
    print(f"       Estado={estado['global']} Riego={estado['riego']}")

    db.guardar(config.COL_SENSOR_READINGS, {
        "timestamp":   ts,
        "tipo":        "sensor_reading",
        "origen":      "RASPBERRY_PI",
        "temperatura": {"valor": l["temperatura"], "unidad": "C"},
        "hum_aire":    {"valor": l["hum_aire"],    "unidad": "%"},
        "hum_suelo_1": {"valor": l["hum_suelo1"],  "estado": estado_suelo1},
        "hum_suelo_2": {"valor": l["hum_suelo2"],  "estado": estado_suelo2},
        "luz":         {"valor": l["luz"]},
        "gas":         {"valor": l["gas"], "estado": estado_gas},
        "estado":      estado["global"],
    })

    db.guardar(config.COL_ACTUATOR_LOGS, {
        "timestamp":  ts, "tipo": "actuator_state",
        "riego":      estado["riego"],
        "ventilador": estado["ventilador"],
        "luces":      estado["luces"],
        "alarma":     estado["alarma"],
        "modo":       estado["modo"],
    })

    if estado["global"] != "NORMAL":
        db.guardar(config.COL_EVENTS, {
            "timestamp": ts, "tipo": "event",
            "estado":    estado["global"],
            "gas":       estado["gas"],
            "riego":     estado["riego"],
            "temp":      l["temperatura"],
            "origen":    "raspberry_pi",
        })

    import csv_manager
    riego1 = 1 if estado["riego"] == "RIEGO_AREA_1" else 0
    riego2 = 1 if estado["riego"] == "RIEGO_AREA_2" else 0
    csv_manager.agregar_fila(
        l["temperatura"], l["hum_aire"], l["hum_suelo1"],
        l["hum_suelo2"], l["luz"], l["gas"], riego1, riego2
    )


# ── Publicadores ───────────────────────────────────────────

def _publicar(topic, datos):
    if not _conectado or _cliente is None:
        return
    try:
        _cliente.publish(topic, json.dumps(datos), qos=0)
        print(f"[MQTT TX] {topic}")
    except Exception as e:
        print(f"[MQTT] Error al publicar: {e}")


def publicar_sensores(lecturas):
    ts = datetime.now().isoformat()
    _publicar(config.TOPIC_TEMPERATURA,      {"valor": lecturas["temperatura"], "unidad": "C",  "timestamp": ts, "origen": "SIMULADO"})
    _publicar(config.TOPIC_HUMEDAD_AMBIENTE, {"valor": lecturas["hum_aire"],    "unidad": "%",  "timestamp": ts, "origen": "SIMULADO"})
    _publicar(config.TOPIC_HUMEDAD_SUELO_1,  {"valor": lecturas["hum_suelo1"],  "estado": lecturas["estado_suelo1"], "area": 1, "timestamp": ts, "origen": "SIMULADO"})
    _publicar(config.TOPIC_HUMEDAD_SUELO_2,  {"valor": lecturas["hum_suelo2"],  "estado": lecturas["estado_suelo2"], "area": 2, "timestamp": ts, "origen": "SIMULADO"})
    _publicar(config.TOPIC_LUZ,              {"valor": lecturas["luz"],  "timestamp": ts, "origen": "SIMULADO"})
    _publicar(config.TOPIC_GAS,              {"valor": lecturas["gas"],  "estado": lecturas["estado_gas"], "timestamp": ts, "origen": "SIMULADO"})


def publicar_actuadores():
    ts = datetime.now().isoformat()
    _publicar(config.TOPIC_RIEGO,        {"estado": estado_sistema["riego"],      "timestamp": ts})
    _publicar(config.TOPIC_VENTILADOR,   {"estado": estado_sistema["ventilador"], "timestamp": ts})
    _publicar(config.TOPIC_LUCES,        {"estado": estado_sistema["luces"],      "timestamp": ts})
    _publicar(config.TOPIC_ALARMA,       {"estado": estado_sistema["alarma"],     "timestamp": ts})
    _publicar(config.TOPIC_ESTADO_GLOBAL,{"estado": estado_sistema["global"], "modo": estado_sistema["modo"], "timestamp": ts})


def publicar_comando_remoto(accion, valor):
    _publicar(config.TOPIC_CONTROL_REMOTO, {
        "accion": accion, "valor": valor,
        "timestamp": datetime.now().isoformat()
    })


# ── Iniciar / Detener ──────────────────────────────────────

def iniciar():
    global _cliente
    client_id = f"InvernaderoG2_backend-{random.randint(0, 9999)}"
    client = mqtt_client.Client(client_id=client_id)
    _cliente = client
    client.on_connect    = on_connect
    client.on_disconnect = on_disconnect
    client.on_message    = on_message
    client.reconnect_delay_set(min_delay=1, max_delay=30)
    client.connect(config.MQTT_BROKER, config.MQTT_PORT, keepalive=60)
    client.loop_start()

    timeout = time.time() + 8
    while not _conectado and time.time() < timeout:
        time.sleep(0.1)

    print("[MQTT] Listo" if _conectado else "[MQTT] Sin conexion al broker")


def detener():
    global _cliente
    if _cliente:
        _cliente.disconnect()
        _cliente.loop_stop()

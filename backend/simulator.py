# ============================================================
# simulator.py - Simulador de sensores y ciclo de lecturas
# Suplanta la funcionalidad del sistema IoT real con GPIO
# hasta que se tenga la Raspberry Pi con sensores fisicos.
# ============================================================

import random
import time
import threading
from datetime import datetime

import config
import database as db
import csv_manager
import mqtt_client as mqtt
from state import (
    estado_sistema, aplicar_logica_automatica,
    clasificar_suelo, clasificar_gas, obtener_estado
)

_corriendo = False
_hilo      = None


# ---- Funciones de lectura simulada -------------------------
# Cada funcion incluye el comentario de como seria en GPIO real.

def leer_temperatura() -> float:
    """
    SIMULADO: DHT22 → 24-36 °C con variacion realista.
    REAL: import Adafruit_DHT
          _, temp = Adafruit_DHT.read_retry(Adafruit_DHT.DHT22, PIN_DHT)
    """
    return round(random.uniform(24.0, 36.0), 1)


def leer_humedad_ambiente() -> float:
    """
    SIMULADO: DHT22 → 40-90 %
    REAL: hum, _ = Adafruit_DHT.read_retry(Adafruit_DHT.DHT22, PIN_DHT)
    """
    return round(random.uniform(40.0, 90.0), 1)


def leer_humedad_suelo(area: int) -> int:
    """
    SIMULADO: Sensor capacitivo → 20-95 %
    REAL: leer_adc(canal_area1 o canal_area2) mapeado a 0-100
    """
    base = estado_sistema["riego"]
    # Simular que el riego aumenta la humedad
    if (area == 1 and base == "RIEGO_AREA_1") or \
       (area == 2 and base == "RIEGO_AREA_2"):
        return random.randint(55, 80)
    return random.randint(20, 85)


def leer_luz() -> int:
    """
    SIMULADO: LDR → 50-900 ADC
    REAL: leer_adc(canal_ldr)  via MCP3008
    """
    hora = datetime.now().hour
    # Simular ciclo dia/noche
    if 7 <= hora <= 19:
        return random.randint(400, 900)
    return random.randint(50, 200)


def leer_gas() -> int:
    """
    SIMULADO: MQ-2/MQ-135 → 80-280 ADC
    REAL: leer_adc(canal_gas)
    """
    return random.randint(80, 250)


# ---- Ciclo de lectura completo -----------------------------

def ciclo_lectura():
    """
    Ejecuta un ciclo completo:
    1. Lee sensores (simulados)
    2. Aplica logica de control
    3. Publica por MQTT
    4. Guarda en MongoDB
    5. Agrega fila al CSV
    """
    ts = datetime.now().isoformat()

    # 1. Leer sensores
    temp       = leer_temperatura()
    hum_aire   = leer_humedad_ambiente()
    hum_suelo1 = leer_humedad_suelo(1)
    hum_suelo2 = leer_humedad_suelo(2)
    luz        = leer_luz()
    gas        = leer_gas()

    estado_suelo1 = clasificar_suelo(hum_suelo1)
    estado_suelo2 = clasificar_suelo(hum_suelo2)
    estado_gas    = clasificar_gas(gas)

    lecturas = {
        "temperatura":  temp,
        "hum_aire":     hum_aire,
        "hum_suelo1":   hum_suelo1,
        "hum_suelo2":   hum_suelo2,
        "luz":          luz,
        "gas":          gas,
        "estado_suelo1": estado_suelo1,
        "estado_suelo2": estado_suelo2,
        "estado_gas":    estado_gas,
    }

    print(f"\n{'='*55}")
    print(f"[LECTURA] {ts}")
    print(f"  Temp: {temp}C | Hum.Aire: {hum_aire}%")
    print(f"  Suelo1: {hum_suelo1}% ({estado_suelo1}) | "
          f"Suelo2: {hum_suelo2}% ({estado_suelo2})")
    print(f"  Luz: {luz} | Gas: {gas} ({estado_gas})")

    # 2. Logica de control automatico
    aplicar_logica_automatica(lecturas)
    estado = obtener_estado()
    print(f"  Estado: {estado['global']} | Riego: {estado['riego']} | "
          f"Vent: {estado['ventilador']} | Luces: {estado['luces']}")

    # 3. Publicar por MQTT
    mqtt.publicar_sensores(lecturas)
    mqtt.publicar_actuadores()

    # 4. Guardar en MongoDB
    doc_lectura = {
        "timestamp":   ts,
        "tipo":        "sensor_reading",
        "origen":      "SIMULADO",
        "temperatura": {"valor": temp,       "unidad": "C"},
        "hum_aire":    {"valor": hum_aire,   "unidad": "%"},
        "hum_suelo_1": {"valor": hum_suelo1, "estado": estado_suelo1},
        "hum_suelo_2": {"valor": hum_suelo2, "estado": estado_suelo2},
        "luz":         {"valor": luz},
        "gas":         {"valor": gas, "estado": estado_gas},
        "estado":      estado["global"],
    }
    db.guardar(config.COL_SENSOR_READINGS, doc_lectura)

    doc_actuadores = {
        "timestamp":  ts,
        "tipo":       "actuator_state",
        "riego":      estado["riego"],
        "ventilador": estado["ventilador"],
        "luces":      estado["luces"],
        "alarma":     estado["alarma"],
        "modo":       estado["modo"],
    }
    db.guardar(config.COL_ACTUATOR_LOGS, doc_actuadores)

    # Guardar evento si hay condicion anormal
    if estado["global"] != "NORMAL":
        db.guardar(config.COL_EVENTS, {
            "timestamp": ts,
            "tipo":      "event",
            "estado":    estado["global"],
            "gas":       estado["gas"],
            "riego":     estado["riego"],
            "temp":      temp,
            "origen":    "control_automatico",
        })

    # 5. Agregar fila al CSV
    riego1 = 1 if estado["riego"] == "RIEGO_AREA_1" else 0
    riego2 = 1 if estado["riego"] == "RIEGO_AREA_2" else 0
    csv_manager.agregar_fila(
        temp, hum_aire, hum_suelo1, hum_suelo2,
        luz, gas, riego1, riego2
    )


# ---- Control del simulador ---------------------------------

def _loop(intervalo: int):
    global _corriendo
    print(f"[SIM] Iniciando ciclos cada {intervalo}s...")
    while _corriendo:
        ciclo_lectura()
        time.sleep(intervalo)
    print("[SIM] Simulador detenido.")


def iniciar(intervalo: int = 15):
    global _corriendo, _hilo
    if _corriendo:
        print("[SIM] Ya esta corriendo.")
        return
    _corriendo = True
    _hilo = threading.Thread(target=_loop, args=(intervalo,), daemon=True)
    _hilo.start()


def detener():
    global _corriendo
    _corriendo = False


def esta_corriendo() -> bool:
    return _corriendo
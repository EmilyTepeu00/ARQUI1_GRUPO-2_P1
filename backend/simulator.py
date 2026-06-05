import random
import time
import threading
from datetime import datetime

import config
import database as db
import csv_manager
import mqtt_client as mqtt
from state import estado_sistema, aplicar_logica_automatica, clasificar_suelo, clasificar_gas, obtener_estado

_corriendo = False
_hilo      = None


def leer_temperatura():
    # REAL: import Adafruit_DHT; _, t = Adafruit_DHT.read_retry(Adafruit_DHT.DHT22, PIN_DHT)
    return round(random.uniform(24.0, 36.0), 1)


def leer_humedad_ambiente():
    # REAL: h, _ = Adafruit_DHT.read_retry(Adafruit_DHT.DHT22, PIN_DHT)
    return round(random.uniform(40.0, 90.0), 1)


def leer_humedad_suelo(area):
    # REAL: leer_adc(canal) mapeado a 0-100
    if (area == 1 and estado_sistema["riego"] == "RIEGO_AREA_1") or \
       (area == 2 and estado_sistema["riego"] == "RIEGO_AREA_2"):
        return random.randint(55, 80)
    return random.randint(20, 85)


def leer_luz():
    # REAL: leer_adc(canal_ldr) via MCP3008
    hora = datetime.now().hour
    if 7 <= hora <= 19:
        return random.randint(400, 900)
    return random.randint(50, 200)


def leer_gas():
    # REAL: leer_adc(canal_gas)
    return random.randint(80, 250)


def ciclo_lectura():
    ts = datetime.now().isoformat()

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
        "temperatura":   temp,
        "hum_aire":      hum_aire,
        "hum_suelo1":    hum_suelo1,
        "hum_suelo2":    hum_suelo2,
        "luz":           luz,
        "gas":           gas,
        "estado_suelo1": estado_suelo1,
        "estado_suelo2": estado_suelo2,
        "estado_gas":    estado_gas,
    }

    print(f"\n{'='*55}")
    print(f"[LECTURA] {ts}")
    print(f"  Temp: {temp}C | Hum.Aire: {hum_aire}%")
    print(f"  Suelo1: {hum_suelo1}% ({estado_suelo1}) | Suelo2: {hum_suelo2}% ({estado_suelo2})")
    print(f"  Luz: {luz} | Gas: {gas} ({estado_gas})")

    aplicar_logica_automatica(lecturas)
    estado = obtener_estado()
    print(f"  Estado: {estado['global']} | Riego: {estado['riego']} | Vent: {estado['ventilador']} | Luces: {estado['luces']}")

    mqtt.publicar_sensores(lecturas)
    mqtt.publicar_actuadores()

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

    db.guardar(config.COL_ACTUATOR_LOGS, {
        "timestamp":  ts,
        "tipo":       "actuator_state",
        "riego":      estado["riego"],
        "ventilador": estado["ventilador"],
        "luces":      estado["luces"],
        "alarma":     estado["alarma"],
        "modo":       estado["modo"],
    })

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

    riego1 = 1 if estado["riego"] == "RIEGO_AREA_1" else 0
    riego2 = 1 if estado["riego"] == "RIEGO_AREA_2" else 0
    csv_manager.agregar_fila(temp, hum_aire, hum_suelo1, hum_suelo2, luz, gas, riego1, riego2)


def _loop(intervalo):
    global _corriendo
    print(f"[SIM] Iniciando ciclos cada {intervalo}s...")
    while _corriendo:
        ciclo_lectura()
        time.sleep(intervalo)
    print("[SIM] Simulador detenido.")


def iniciar(intervalo=15):
    global _corriendo, _hilo
    if _corriendo:
        return
    _corriendo = True
    _hilo = threading.Thread(target=_loop, args=(intervalo,), daemon=True)
    _hilo.start()


def detener():
    global _corriendo
    _corriendo = False


def esta_corriendo():
    return _corriendo

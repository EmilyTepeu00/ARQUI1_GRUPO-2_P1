"""
mqtt_rasp.py — Cliente MQTT para la Raspberry Pi
Publica lecturas de sensores y recibe comandos del dashboard.
"""

import json
import random
import time
from datetime import datetime
from paho.mqtt import client as mqtt_client

import config_rasp as cfg

_cliente   = None
_conectado = False
_cb_comando = None  # callback para procesar comandos recibidos


def on_connect(client, userdata, flags, rc):
    global _conectado
    if rc == 0:
        print("[MQTT] Conectado al broker OK")
        _conectado = True
        client.subscribe(f"{cfg.MQTT_PREFIX}/#")
        print(f"[MQTT] Suscrito a {cfg.MQTT_PREFIX}/#")
    else:
        print(f"[MQTT] Fallo rc={rc}")
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

        if topic in (cfg.TOPIC_CONTROL_REMOTO, cfg.TOPIC_CONTROL_MANUAL):
            if _cb_comando:
                _cb_comando(payload)
    except Exception as e:
        print(f"[MQTT] Error en mensaje: {e}")


def _pub(topic, datos):
    if not _conectado or _cliente is None:
        return
    try:
        _cliente.publish(topic, json.dumps(datos), qos=0)
        print(f"[MQTT TX] {topic}")
    except Exception as e:
        print(f"[MQTT] Error: {e}")


# ── Publicadores de sensores ───────────────────────────────

def publicar_temperatura(valor):
    _pub(cfg.TOPIC_TEMPERATURA, {
        "valor": valor, "unidad": "C",
        "timestamp": datetime.now().isoformat(), "origen": "DHT22"
    })


def publicar_humedad_ambiente(valor):
    _pub(cfg.TOPIC_HUMEDAD_AMBIENTE, {
        "valor": valor, "unidad": "%",
        "timestamp": datetime.now().isoformat(), "origen": "DHT22"
    })


def publicar_humedad_suelo(area, valor, estado):
    topic = cfg.TOPIC_HUMEDAD_SUELO_1 if area == 1 else cfg.TOPIC_HUMEDAD_SUELO_2
    _pub(topic, {
        "valor": valor, "estado": estado, "area": area,
        "timestamp": datetime.now().isoformat(),
        "origen": f"sensor_suelo_area{area}"
    })


def publicar_luz(valor):
    _pub(cfg.TOPIC_LUZ, {
        "valor": valor,
        "timestamp": datetime.now().isoformat(), "origen": "LDR"
    })


def publicar_gas(valor, estado):
    _pub(cfg.TOPIC_GAS, {
        "valor": valor, "estado": estado,
        "timestamp": datetime.now().isoformat(), "origen": "MQ2"
    })


def publicar_estado_global(estado, modo):
    _pub(cfg.TOPIC_ESTADO_GLOBAL, {
        "estado": estado, "modo": modo,
        "timestamp": datetime.now().isoformat()
    })


# ── Iniciar / Detener ──────────────────────────────────────

def iniciar(cb_comando=None):
    global _cliente, _cb_comando
    _cb_comando = cb_comando

    client_id = f"InvernaderoG2_rasp-{random.randint(0, 9999)}"
    client = mqtt_client.Client(client_id=client_id)
    _cliente = client
    client.on_connect    = on_connect
    client.on_disconnect = on_disconnect
    client.on_message    = on_message
    client.reconnect_delay_set(min_delay=1, max_delay=30)
    client.connect(cfg.MQTT_BROKER, cfg.MQTT_PORT, keepalive=60)
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

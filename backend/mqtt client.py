# ============================================================
# mqtt_client.py - Manejo de MQTT
# Publica lecturas de sensores y recibe comandos remotos
# ============================================================

import json
import random
import time
from datetime import datetime
from paho.mqtt import client as mqtt_client

import config
import database as db
from state import estado_sistema, procesar_comando

_cliente     = None
_conectado   = False


# ---- Callbacks ---------------------------------------------

def on_connect(client, userdata, flags, rc):
    global _conectado
    if rc == 0:
        print("[MQTT] Conectado al broker OK")
        _conectado = True
        client.subscribe(f"{config.MQTT_PREFIX}/#")
        print(f"[MQTT] Suscrito a {config.MQTT_PREFIX}/#")
    else:
        print(f"[MQTT] Fallo de conexion, codigo: {rc}")
        _conectado = False


def on_disconnect(client, userdata, rc):
    global _conectado
    _conectado = False
    if rc != 0:
        print("[MQTT] Desconexion inesperada. Reconectando...")


def on_message(client, userdata, msg):
    """
    Recibe mensajes de todos los topics suscritos.
    Solo procesa topics de control remoto/manual.
    """
    try:
        payload = json.loads(msg.payload.decode())
        topic   = msg.topic

        if topic in (config.TOPIC_CONTROL_REMOTO, config.TOPIC_CONTROL_MANUAL):
            origen = "REMOTO" if topic == config.TOPIC_CONTROL_REMOTO else "MANUAL"
            print(f"\n[MQTT CMD {origen}] {topic}: {payload}")
            procesar_comando(payload, origen)
        else:
            print(f"[MQTT] {topic}: {payload}")

    except json.JSONDecodeError:
        pass
    except Exception as e:
        print(f"[MQTT] Error procesando mensaje: {e}")


# ---- Publicadores ------------------------------------------

def _publicar(topic: str, datos: dict):
    global _cliente, _conectado
    if not _conectado or _cliente is None:
        print(f"[MQTT] Sin conexion - no se publico en {topic}")
        return
    mensaje   = json.dumps(datos)
    resultado = _cliente.publish(topic, mensaje, qos=0)
    if resultado[0] == 0:
        print(f"[MQTT ->] {topic}")
    else:
        print(f"[MQTT] ERROR al publicar en {topic}")


def publicar_sensores(lecturas: dict):
    """Publica todas las lecturas de sensores por MQTT."""
    ts = datetime.now().isoformat()

    _publicar(config.TOPIC_TEMPERATURA, {
        "valor": lecturas["temperatura"],
        "unidad": "C",
        "timestamp": ts,
        "origen": "SIMULADO"
    })

    _publicar(config.TOPIC_HUMEDAD_AMBIENTE, {
        "valor": lecturas["hum_aire"],
        "unidad": "%",
        "timestamp": ts,
        "origen": "SIMULADO"
    })

    _publicar(config.TOPIC_HUMEDAD_SUELO_1, {
        "valor": lecturas["hum_suelo1"],
        "estado": lecturas["estado_suelo1"],
        "area": 1,
        "timestamp": ts,
        "origen": "SIMULADO"
    })

    _publicar(config.TOPIC_HUMEDAD_SUELO_2, {
        "valor": lecturas["hum_suelo2"],
        "estado": lecturas["estado_suelo2"],
        "area": 2,
        "timestamp": ts,
        "origen": "SIMULADO"
    })

    _publicar(config.TOPIC_LUZ, {
        "valor": lecturas["luz"],
        "timestamp": ts,
        "origen": "SIMULADO"
    })

    _publicar(config.TOPIC_GAS, {
        "valor": lecturas["gas"],
        "estado": lecturas["estado_gas"],
        "timestamp": ts,
        "origen": "SIMULADO"
    })


def publicar_actuadores():
    """Publica el estado actual de todos los actuadores."""
    ts = datetime.now().isoformat()
    _publicar(config.TOPIC_RIEGO,      {"estado": estado_sistema["riego"],      "timestamp": ts})
    _publicar(config.TOPIC_VENTILADOR, {"estado": estado_sistema["ventilador"], "timestamp": ts})
    _publicar(config.TOPIC_LUCES,      {"estado": estado_sistema["luces"],      "timestamp": ts})
    _publicar(config.TOPIC_ALARMA,     {"estado": estado_sistema["alarma"],     "timestamp": ts})
    _publicar(config.TOPIC_ESTADO_GLOBAL, {
        "estado":    estado_sistema["global"],
        "modo":      estado_sistema["modo"],
        "timestamp": ts
    })


def publicar_comando_remoto(accion: str, valor: str):
    """
    El backend publica un comando remoto via MQTT
    (usado cuando el dashboard envia un comando HTTP al backend).
    """
    _publicar(config.TOPIC_CONTROL_REMOTO, {
        "accion":    accion,
        "valor":     valor,
        "timestamp": datetime.now().isoformat()
    })


# ---- Iniciar / Detener -------------------------------------

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

    # Esperar conexion
    timeout = time.time() + 8
    while not _conectado and time.time() < timeout:
        time.sleep(0.1)

    if _conectado:
        print("[MQTT] Listo")
    else:
        print("[MQTT] ADVERTENCIA: no se conecto en 8 segundos")


def detener():
    global _cliente
    if _cliente:
        _cliente.disconnect()
        _cliente.loop_stop()
        print("[MQTT] Desconectado")
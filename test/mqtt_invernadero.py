import random
import time
import json
from datetime import datetime
from paho.mqtt import client as mqtt_client


BROKER    = "broker.emqx.io"
PORT      = 1883
CLIENT_ID = f"InvernaderoG2_ARQUI1-pi-{random.randint(0, 9999)}"
USERNAME  = None
PASSWORD  = None

TOPIC_TEMPERATURA      = "InvernaderoG2_ARQUI1/sensores/temperatura"
TOPIC_HUMEDAD_AMBIENTE = "InvernaderoG2_ARQUI1/sensores/humedad_ambiente"
TOPIC_HUMEDAD_SUELO_1  = "InvernaderoG2_ARQUI1/sensores/humedad_suelo_area1"
TOPIC_HUMEDAD_SUELO_2  = "InvernaderoG2_ARQUI1/sensores/humedad_suelo_area2"
TOPIC_LUZ              = "InvernaderoG2_ARQUI1/sensores/luz"
TOPIC_GAS              = "InvernaderoG2_ARQUI1/sensores/gas"

TOPIC_RIEGO            = "InvernaderoG2_ARQUI1/actuadores/riego"
TOPIC_RIEGO_AREA1      = "InvernaderoG2_ARQUI1/actuadores/riego_area1"
TOPIC_RIEGO_AREA2      = "InvernaderoG2_ARQUI1/actuadores/riego_area2"
TOPIC_VENTILADOR       = "InvernaderoG2_ARQUI1/actuadores/ventilador"
TOPIC_LUCES            = "InvernaderoG2_ARQUI1/actuadores/luces"
TOPIC_ALARMA           = "InvernaderoG2_ARQUI1/actuadores/alarma"

TOPIC_ESTADO_GLOBAL    = "InvernaderoG2_ARQUI1/estado/global"
TOPIC_CONTROL_REMOTO   = "InvernaderoG2_ARQUI1/control/remoto"
TOPIC_CONTROL_MANUAL   = "InvernaderoG2_ARQUI1/control/manual"

mqtt_connected = False
cliente_mqtt   = None


def on_connect(client, userdata, flags, rc):
    global mqtt_connected
    if rc == 0:
        print("[MQTT] Conectado al broker")
        mqtt_connected = True
        client.subscribe("InvernaderoG2_ARQUI1/#")
        print("[MQTT] Suscrito a InvernaderoG2_ARQUI1/#")
    else:
        print(f"[MQTT] Fallo de conexion, codigo: {rc}")
        mqtt_connected = False


def on_disconnect(client, userdata, rc):
    global mqtt_connected
    mqtt_connected = False
    if rc != 0:
        print("[MQTT] Desconexion inesperada. Reconectando...")


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode())
        print(f"[MQTT] Recibido [{msg.topic}]: {payload}")

        if msg.topic == TOPIC_CONTROL_REMOTO:
            procesar_comando(payload)
        elif msg.topic == TOPIC_CONTROL_MANUAL:
            procesar_comando(payload)

    except Exception as e:
        print(f"[MQTT] Error procesando mensaje: {e}")



def procesar_comando(payload: dict):
    accion = payload.get("accion", "").upper()
    valor  = payload.get("valor",  "").upper()

    if accion == "RIEGO_AREA1":
        print(f"[CMD] Riego Area 1 -> {valor}")

    elif accion == "RIEGO_AREA2":
        print(f"[CMD] Riego Area 2 -> {valor}")

    elif accion == "VENTILADOR":
        print(f"[CMD] Ventilador -> {valor}")

    elif accion == "LUCES":
        print(f"[CMD] Luces -> {valor}")

    elif accion == "ALARMA":
        print(f"[CMD] Alarma -> {valor}")

    elif accion == "MODO":
        print(f"[CMD] Modo -> {valor}")

    else:
        print(f"[CMD] Accion desconocida: {accion}")


def _publicar(topic: str, datos: dict):
    global cliente_mqtt, mqtt_connected
    if not mqtt_connected or cliente_mqtt is None:
        print(f"[MQTT] Sin conexion, no se publico en {topic}")
        return
    mensaje   = json.dumps(datos)
    resultado = cliente_mqtt.publish(topic, mensaje, qos=0)
    if resultado[0] == 0:
        print(f"[MQTT] OK -> {topic}: {mensaje}")
    else:
        print(f"[MQTT] ERROR -> {topic}")


def publicar_temperatura(valor: float):
    _publicar(TOPIC_TEMPERATURA, {
        "valor": valor,
        "unidad": "C",
        "timestamp": datetime.now().isoformat(),
        "origen": "DHT22"
    })


def publicar_humedad_ambiente(valor: float):
    _publicar(TOPIC_HUMEDAD_AMBIENTE, {
        "valor": valor,
        "unidad": "%",
        "timestamp": datetime.now().isoformat(),
        "origen": "DHT22"
    })


def publicar_humedad_suelo(area: int, valor: int, estado: str):
    topic = TOPIC_HUMEDAD_SUELO_1 if area == 1 else TOPIC_HUMEDAD_SUELO_2
    _publicar(topic, {
        "valor": valor,
        "estado": estado,
        "area": area,
        "timestamp": datetime.now().isoformat(),
        "origen": f"sensor_suelo_area{area}"
    })


def publicar_luz(valor: int):
    _publicar(TOPIC_LUZ, {
        "valor": valor,
        "timestamp": datetime.now().isoformat(),
        "origen": "LDR"
    })


def publicar_gas(valor: int, estado: str):
    _publicar(TOPIC_GAS, {
        "valor": valor,
        "estado": estado,
        "timestamp": datetime.now().isoformat(),
        "origen": "MQ2"
    })


def publicar_actuador(topic: str, estado: str):
    _publicar(topic, {
        "estado": estado,
        "timestamp": datetime.now().isoformat()
    })


def publicar_estado_global(estado: str):
    _publicar(TOPIC_ESTADO_GLOBAL, {
        "estado": estado,
        "timestamp": datetime.now().isoformat()
    })


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

    timeout = time.time() + 5
    while not mqtt_connected and time.time() < timeout:
        time.sleep(0.1)

    if mqtt_connected:
        print("[MQTT] Listo")
    else:
        print("[MQTT] ADVERTENCIA: no se conecto en 5 segundos")

    return client

def detener_mqtt():
    global cliente_mqtt
    if cliente_mqtt:
        cliente_mqtt.disconnect()
        cliente_mqtt.loop_stop()
        print("[MQTT] Desconectado")
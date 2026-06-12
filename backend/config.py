# MongoDB
MONGO_URI = (
    "mongodb+srv://Invernadero_user:Invernadero2026"
    "@invernadero-cluster.gdzxx9p.mongodb.net/"
    "?appName=Invernadero-cluster"
)
MONGO_DB_NAME = "Invernadero"

COL_SENSOR_READINGS = "sensor_readings"
COL_EVENTS          = "events"
COL_COMMANDS        = "commands"
COL_SYSTEM_STATUS   = "system_status"
COL_ACTUATOR_LOGS   = "actuator_logs"
COL_ARM64_RESULTS   = "arm64_results"

# MQTT
MQTT_BROKER = "broker.emqx.io"
MQTT_PORT   = 1883
MQTT_PREFIX = "InvernaderoG2_ARQUI1"

TOPIC_TEMPERATURA      = f"{MQTT_PREFIX}/sensores/temperatura"
TOPIC_HUMEDAD_AMBIENTE = f"{MQTT_PREFIX}/sensores/humedad_ambiente"
TOPIC_HUMEDAD_SUELO_1  = f"{MQTT_PREFIX}/sensores/humedad_suelo_area1"
TOPIC_HUMEDAD_SUELO_2  = f"{MQTT_PREFIX}/sensores/humedad_suelo_area2"
TOPIC_LUZ              = f"{MQTT_PREFIX}/sensores/luz"
TOPIC_GAS              = f"{MQTT_PREFIX}/sensores/gas"

TOPIC_RIEGO        = f"{MQTT_PREFIX}/actuadores/riego"
TOPIC_RIEGO_AREA1  = f"{MQTT_PREFIX}/actuadores/riego_area1"
TOPIC_RIEGO_AREA2  = f"{MQTT_PREFIX}/actuadores/riego_area2"
TOPIC_VENTILADOR   = f"{MQTT_PREFIX}/actuadores/ventilador"
TOPIC_LUCES        = f"{MQTT_PREFIX}/actuadores/luces"
TOPIC_ALARMA       = f"{MQTT_PREFIX}/actuadores/alarma"

TOPIC_ESTADO_GLOBAL  = f"{MQTT_PREFIX}/estado/global"
TOPIC_CONTROL_REMOTO = f"{MQTT_PREFIX}/control/remoto"
TOPIC_CONTROL_MANUAL = f"{MQTT_PREFIX}/control/manual"

# CSV 
CSV_FILE     = "lecturas.csv"
CSV_MAX_ROWS = 30
CSV_HEADERS  = [
    "ID","TEMP","HUM_AIRE","HUM_SUELO_1",
    "HUM_SUELO_2","LUZ","GAS","RIEGO_1","RIEGO_2"
]

# Umbrales
UMBRAL_TEMP_ALTA       = 32.0
UMBRAL_HUMEDAD_BAJA    = 40
UMBRAL_HUMEDAD_NORMAL  = 70
UMBRAL_LUZ_BAJA        = 300
UMBRAL_GAS_ADVERTENCIA = 80
UMBRAL_GAS_EMERGENCIA  = 90

# Flask
FLASK_HOST = "0.0.0.0"
FLASK_PORT = 5000

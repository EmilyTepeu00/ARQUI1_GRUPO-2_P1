# ── MQTT ───────────────────────────────────────────────────
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

# ── Pines GPIO (BCM) ────────────────────────────────────────
# Sensores
PIN_DHT22       = 4      # DHT22 → temperatura y humedad ambiente
PIN_LDR_CLK     = 11     # MCP3008 SPI CLK  (para LDR y sensores analogicos)
PIN_LDR_MISO    = 9      # MCP3008 SPI MISO
PIN_LDR_MOSI    = 10     # MCP3008 SPI MOSI
PIN_LDR_CS      = 8      # MCP3008 CS/SS
# Canales del MCP3008
CANAL_SUELO_1   = 0      # Sensor humedad suelo area 1
CANAL_SUELO_2   = 1      # Sensor humedad suelo area 2
CANAL_LDR       = 2      # Sensor de luz LDR
CANAL_GAS       = 3      # Sensor gas MQ-2/MQ-135

# Actuadores
PIN_BOMBA_1     = 17     # Relé bomba riego area 1
PIN_BOMBA_2     = 27     # Relé bomba riego area 2
PIN_VENTILADOR  = 22     # Relé / transistor ventilador
PIN_LED_LUCES_1 = 23     # LEDs iluminacion area 1
PIN_LED_LUCES_2 = 24     # LEDs iluminacion area 2
PIN_BUZZER      = 25     # Buzzer activo

# LEDs de estado
PIN_LED_VERDE   = 5      # Estado NORMAL
PIN_LED_AMARILLO= 6      # Estado ADVERTENCIA / RIEGO_ACTIVO
PIN_LED_ROJO    = 13     # Estado EMERGENCIA

# Botones fisicos (pull-up interno)
PIN_BTN_MODO    = 16     # Boton 1: cambiar AUTO / MANUAL
PIN_BTN_RIEGO   = 19     # Boton 2: riego manual
PIN_BTN_LUCES   = 20     # Boton 3: luces manual
PIN_BTN_RESET   = 21     # Boton 4: silenciar alarma / reset

# LCD I2C
LCD_ADDRESS     = 0x27   # Direccion I2C del modulo LCD (0x27 o 0x3F)
LCD_COLS        = 16
LCD_ROWS        = 2

# ── Umbrales ────────────────────────────────────────────────
UMBRAL_TEMP_ALTA       = 32.0
UMBRAL_HUMEDAD_BAJA    = 40
UMBRAL_HUMEDAD_NORMAL  = 70
UMBRAL_LUZ_BAJA        = 300
UMBRAL_GAS_ADVERTENCIA = 150
UMBRAL_GAS_EMERGENCIA  = 200

# Duracion del riego en segundos
DURACION_RIEGO    = 10
PAUSA_ENTRE_RIEGO = 30

# Intervalo de lectura de sensores (segundos)
INTERVALO_LECTURA = 15

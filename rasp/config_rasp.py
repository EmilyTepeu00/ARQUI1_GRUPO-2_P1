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

# Pines GPIO (BCM)
# Sensores digitales
PIN_DHT11      = 4    # DHT11 — datos
PIN_SUELO_1    = 16   # Sensor humedad suelo área 1 — D0
PIN_SUELO_2    = 26   # Sensor humedad suelo área 2 — D0
PIN_LDR        = 12   # Módulo LDR — D0

# MCP3008 SPI (para MQ-135 analógico)
PIN_SPI_CLK    = 11   # CLK
PIN_SPI_MISO   = 9    # MISO (DOUT del MCP3008)
PIN_SPI_MOSI   = 10   # MOSI (DIN del MCP3008)
PIN_SPI_CS     = 8    # CS/SS
CANAL_GAS      = 0    # MQ-135 → canal 0 del MCP3008

# Actuadores
PIN_RELE_BOMBA = 17   # Relé 1 → bomba de agua
PIN_RELE_VENT  = 22   # Relé 2 → ventilador
PIN_LED_LUZ_1  = 23   # LEDs iluminación área 1
PIN_LED_LUZ_2  = 24   # LEDs iluminación área 2
PIN_BUZZER     = 27   # Buzzer activo

# LEDs de estado
PIN_LED_VERDE    = 5  # Estado NORMAL
PIN_LED_AMARILLO = 6  # Estado ADVERTENCIA / RIEGO_ACTIVO
PIN_LED_ROJO     = 13 # Estado EMERGENCIA

# Botones físicos (pull-up interno)
PIN_BTN_MODO   = 14   # Botón 1 — cambiar AUTO/MANUAL
PIN_BTN_RIEGO  = 15   # Botón 2 — riego manual
PIN_BTN_LUCES  = 18   # Botón 3 — luces manual
PIN_BTN_RESET  = 20   # Botón 4 — silenciar alarma / reset

# LCD I2C
LCD_ADDRESS    = 0x27 # Dirección I2C (probar 0x3F si no funciona)
LCD_COLS       = 16
LCD_ROWS       = 2

# Umbrales
UMBRAL_TEMP_ALTA       = 32.0
UMBRAL_LUZ_BAJA        = 300   # LDR digital: 0=oscuro, 1=luz
UMBRAL_GAS_EMERGENCIA = 90
UMBRAL_GAS_ADVERTENCIA = 80

# Duración del riego (segundos)
DURACION_RIEGO    = 10
PAUSA_ENTRE_RIEGO = 30

# Intervalo de lectura (segundos)
INTERVALO_LECTURA = 15

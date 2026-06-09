import Adafruit_DHT
import RPi.GPIO as GPIO
import config_rasp as cfg

GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)


def inicializar():
    # Entradas digitales
    GPIO.setup(cfg.PIN_DHT11,   GPIO.IN)
    GPIO.setup(cfg.PIN_SUELO_1, GPIO.IN)
    GPIO.setup(cfg.PIN_SUELO_2, GPIO.IN)
    GPIO.setup(cfg.PIN_LDR,     GPIO.IN)

    # SPI bit-banging para MCP3008
    GPIO.setup(cfg.PIN_SPI_CLK,  GPIO.OUT)
    GPIO.setup(cfg.PIN_SPI_MOSI, GPIO.OUT)
    GPIO.setup(cfg.PIN_SPI_MISO, GPIO.IN)
    GPIO.setup(cfg.PIN_SPI_CS,   GPIO.OUT)

    print("[SENSORES] GPIO inicializado")


def _leer_adc(canal):
    """Lee un canal del MCP3008 via SPI bit-banging. Retorna 0-1023."""
    GPIO.output(cfg.PIN_SPI_CS,  GPIO.HIGH)
    GPIO.output(cfg.PIN_SPI_CLK, GPIO.LOW)
    GPIO.output(cfg.PIN_SPI_CS,  GPIO.LOW)

    cmd = canal | 0x18
    cmd <<= 3
    for _ in range(5):
        GPIO.output(cfg.PIN_SPI_MOSI, cmd & 0x80)
        cmd <<= 1
        GPIO.output(cfg.PIN_SPI_CLK, GPIO.HIGH)
        GPIO.output(cfg.PIN_SPI_CLK, GPIO.LOW)

    resultado = 0
    for _ in range(12):
        GPIO.output(cfg.PIN_SPI_CLK, GPIO.HIGH)
        GPIO.output(cfg.PIN_SPI_CLK, GPIO.LOW)
        resultado <<= 1
        if GPIO.input(cfg.PIN_SPI_MISO):
            resultado |= 0x1

    GPIO.output(cfg.PIN_SPI_CS, GPIO.HIGH)
    return resultado >> 1


def leer_temperatura_humedad():
    """DHT11 — retorna (temperatura, humedad)."""
    hum, temp = Adafruit_DHT.read_retry(Adafruit_DHT.DHT11, cfg.PIN_DHT11)
    if temp is None or hum is None:
        print("[SENSOR] DHT11 error — reintentando")
        return leer_temperatura_humedad()
    return (round(temp, 1), round(hum, 1))


def leer_humedad_suelo(area):
    """
    Sensor resistivo con módulo D0.
    Retorna: "SECO" si D0=HIGH (sin humedad), "NORMAL" si D0=LOW (con humedad).
    El potenciómetro del módulo define el umbral.
    """
    pin = cfg.PIN_SUELO_1 if area == 1 else cfg.PIN_SUELO_2
    valor = GPIO.input(pin)
    # La mayoría de módulos: HIGH = seco, LOW = húmedo
    return "SECO" if valor == GPIO.HIGH else "NORMAL"


def leer_luz():
    """
    Módulo LDR con D0.
    Retorna: "BAJO" si D0=HIGH (poca luz), "NORMAL" si D0=LOW (hay luz).
    """
    valor = GPIO.input(cfg.PIN_LDR)
    return "BAJO" if valor == GPIO.HIGH else "NORMAL"


def leer_gas():
    """
    MQ-135 via A0 → MCP3008 canal 0.
    Retorna valor ADC 0-1023.
    """
    return _leer_adc(cfg.CANAL_GAS)


def clasificar_suelo(estado):
    """El sensor ya devuelve SECO o NORMAL directamente."""
    return estado


def clasificar_gas(valor):
    if valor >= cfg.UMBRAL_GAS_EMERGENCIA:
        return "GAS_EMERGENCIA"
    elif valor >= cfg.UMBRAL_GAS_ADVERTENCIA:
        return "GAS_ADVERTENCIA"
    return "GAS_NORMAL"


def clasificar_luz(estado):
    return estado

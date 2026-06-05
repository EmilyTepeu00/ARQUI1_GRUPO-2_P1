"""
sensores.py — Lectura de sensores
Intenta importar las librerias GPIO reales.
Si no estan disponibles (desarrollo en PC) usa datos simulados.
"""

import random
from datetime import datetime

try:
    import Adafruit_DHT
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    MODO_REAL = True
    print("[SENSORES] GPIO real disponible")
except ImportError:
    MODO_REAL = False
    print("[SENSORES] GPIO no disponible — usando simulacion")

import config_rasp as cfg


# ── MCP3008 (ADC para sensores analogicos) ─────────────────

def _leer_adc(canal):
    """Lee un canal del MCP3008 via SPI bit-banging. Retorna 0-1023."""
    if not MODO_REAL:
        return random.randint(200, 800)

    import RPi.GPIO as GPIO
    GPIO.output(cfg.PIN_LDR_CS, GPIO.HIGH)
    GPIO.output(cfg.PIN_LDR_CLK, GPIO.LOW)
    GPIO.output(cfg.PIN_LDR_CS, GPIO.LOW)

    cmd = canal | 0x18
    cmd <<= 3
    for _ in range(5):
        GPIO.output(cfg.PIN_LDR_MOSI, cmd & 0x80)
        cmd <<= 1
        GPIO.output(cfg.PIN_LDR_CLK, GPIO.HIGH)
        GPIO.output(cfg.PIN_LDR_CLK, GPIO.LOW)

    resultado = 0
    for _ in range(12):
        GPIO.output(cfg.PIN_LDR_CLK, GPIO.HIGH)
        GPIO.output(cfg.PIN_LDR_CLK, GPIO.LOW)
        resultado <<= 1
        if GPIO.input(cfg.PIN_LDR_MISO):
            resultado |= 0x1

    GPIO.output(cfg.PIN_LDR_CS, GPIO.HIGH)
    return resultado >> 1


def inicializar_gpio_sensores():
    if not MODO_REAL:
        return
    import RPi.GPIO as GPIO
    GPIO.setup(cfg.PIN_LDR_CLK,  GPIO.OUT)
    GPIO.setup(cfg.PIN_LDR_MOSI, GPIO.OUT)
    GPIO.setup(cfg.PIN_LDR_MISO, GPIO.IN)
    GPIO.setup(cfg.PIN_LDR_CS,   GPIO.OUT)


# ── Funciones de lectura ───────────────────────────────────

def leer_temperatura_humedad():
    """
    Retorna (temperatura, humedad_ambiente).
    Real: DHT22 en PIN_DHT22.
    """
    if MODO_REAL:
        hum, temp = Adafruit_DHT.read_retry(Adafruit_DHT.DHT22, cfg.PIN_DHT22)
        if temp is None or hum is None:
            print("[SENSOR] DHT22 error de lectura — reintentando")
            return (25.0, 60.0)
        return (round(temp, 1), round(hum, 1))
    else:
        hora = datetime.now().hour
        # Simula mas calor durante el dia
        base_temp = 28.0 if 8 <= hora <= 18 else 24.0
        return (
            round(random.uniform(base_temp, base_temp + 8), 1),
            round(random.uniform(40.0, 90.0), 1)
        )


def leer_humedad_suelo(area):
    """
    Retorna humedad del suelo en % (0-100).
    Real: sensor capacitivo en canal MCP3008.
    """
    if MODO_REAL:
        canal = cfg.CANAL_SUELO_1 if area == 1 else cfg.CANAL_SUELO_2
        valor_adc = _leer_adc(canal)
        # El sensor da ~1023 en seco y ~300 en mojado → invertimos y mapeamos
        humedad = int((1023 - valor_adc) / 1023 * 100)
        return max(0, min(100, humedad))
    else:
        return random.randint(20, 85)


def leer_luz():
    """
    Retorna nivel de luz (0-1023 del ADC).
    Real: LDR en canal MCP3008.
    """
    if MODO_REAL:
        return _leer_adc(cfg.CANAL_LDR)
    else:
        hora = datetime.now().hour
        if 7 <= hora <= 19:
            return random.randint(400, 900)
        return random.randint(50, 200)


def leer_gas():
    """
    Retorna nivel de gas (0-1023 del ADC).
    Real: MQ-2 o MQ-135 en canal MCP3008.
    """
    if MODO_REAL:
        return _leer_adc(cfg.CANAL_GAS)
    else:
        return random.randint(80, 250)


def clasificar_suelo(valor):
    if valor < cfg.UMBRAL_HUMEDAD_BAJA:
        return "SECO"
    elif valor <= cfg.UMBRAL_HUMEDAD_NORMAL:
        return "NORMAL"
    return "SATURADO"


def clasificar_gas(valor):
    if valor >= cfg.UMBRAL_GAS_EMERGENCIA:
        return "GAS_EMERGENCIA"
    elif valor >= cfg.UMBRAL_GAS_ADVERTENCIA:
        return "GAS_ADVERTENCIA"
    return "GAS_NORMAL"

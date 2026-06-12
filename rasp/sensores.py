import adafruit_dht
import board
import RPi.GPIO as GPIO
import serial
import time as _time
import config_rasp as cfg

GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)

_arduino = None
_ultima_lectura_arduino = {}


def inicializar():
    GPIO.setup(cfg.PIN_SUELO_1, GPIO.IN)
    GPIO.setup(cfg.PIN_SUELO_2, GPIO.IN)
    GPIO.setup(cfg.PIN_LDR,     GPIO.IN)
    print("[SENSORES] GPIO inicializado")


def inicializar_arduino():
    global _arduino
    try:
        _arduino = serial.Serial('/dev/ttyACM0', 9600, timeout=2)
        _time.sleep(2)
        print("[ARDUINO] Conectado OK")
    except Exception as e:
        print(f"[ARDUINO] Error: {e}")


def _leer_arduino():
    global _ultima_lectura_arduino
    try:
        _arduino.reset_input_buffer()
        linea = _arduino.readline().decode('utf-8').strip()
        if not linea:
            return _ultima_lectura_arduino
        datos = {}
        for parte in linea.split(','):
            if ':' in parte:
                k, v = parte.split(':')
                datos[k.strip()] = int(v.strip())
        if datos:
            _ultima_lectura_arduino = datos
        return datos
    except Exception as e:
        print(f"[ARDUINO] Error lectura: {e}")
        return _ultima_lectura_arduino


def leer_temperatura_humedad():
    try:
        dht = adafruit_dht.DHT11(board.D4, use_pulseio=False)
        temp = dht.temperature
        hum  = dht.humidity
        dht.exit()
        if temp is None or hum is None:
            return leer_temperatura_humedad()
        return (round(temp, 1), round(hum, 1))
    except Exception as e:
        print(f"[SENSOR] DHT11 error: {e}")
        return leer_temperatura_humedad()


def leer_humedad_suelo_valor(area):
    datos = _leer_arduino()
    if datos:
        key = 'SUELO1' if area == 1 else 'SUELO2'
        if key in datos:
            return datos[key]
    return 1023


def leer_humedad_suelo(area):
    valor = leer_humedad_suelo_valor(area)
    return "SECO" if valor > 800 else "NORMAL"


def leer_luz():
    valor = GPIO.input(cfg.PIN_LDR)
    return "BAJO" if valor == GPIO.HIGH else "NORMAL"


def leer_gas():
    datos = _leer_arduino()
    if datos and 'GAS' in datos:
        return datos['GAS']
    return 0


def clasificar_suelo(estado):
    return estado


def clasificar_gas(valor):
    if valor >= cfg.UMBRAL_GAS_EMERGENCIA:
        return "GAS_EMERGENCIA"
    elif valor >= cfg.UMBRAL_GAS_ADVERTENCIA:
        return "GAS_ADVERTENCIA"
    return "GAS_NORMAL"


def clasificar_luz(estado):
    return estado

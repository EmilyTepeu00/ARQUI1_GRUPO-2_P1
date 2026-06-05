"""
botones.py — Lectura de botones fisicos
Con fallback si no hay GPIO.
"""

try:
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    MODO_REAL = True
except ImportError:
    MODO_REAL = False

import config_rasp as cfg

_callbacks = {}


def inicializar():
    if not MODO_REAL:
        print("[BOTONES] Modo simulado — sin GPIO")
        return

    botones = [
        cfg.PIN_BTN_MODO,
        cfg.PIN_BTN_RIEGO,
        cfg.PIN_BTN_LUCES,
        cfg.PIN_BTN_RESET,
    ]
    for pin in botones:
        GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)

    print("[BOTONES] GPIO inicializado")


def registrar(pin, callback):
    """Registra una funcion para cuando se presione el boton."""
    _callbacks[pin] = callback
    if MODO_REAL:
        GPIO.add_event_detect(
            pin,
            GPIO.FALLING,
            callback=lambda ch: callback(),
            bouncetime=300
        )


def registrar_todos(cb_modo, cb_riego, cb_luces, cb_reset):
    registrar(cfg.PIN_BTN_MODO,  cb_modo)
    registrar(cfg.PIN_BTN_RIEGO, cb_riego)
    registrar(cfg.PIN_BTN_LUCES, cb_luces)
    registrar(cfg.PIN_BTN_RESET, cb_reset)

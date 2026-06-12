import RPi.GPIO as GPIO
import threading
import time
import config_rasp as cfg

GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)

_callbacks = {}
_corriendo = True


def inicializar():
    for pin in [cfg.PIN_BTN_MODO, cfg.PIN_BTN_RIEGO,
                cfg.PIN_BTN_LUCES, cfg.PIN_BTN_RESET]:
        GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    print("[BOTONES] GPIO inicializado")


def registrar_todos(cb_modo, cb_riego, cb_luces, cb_reset):
    _callbacks[cfg.PIN_BTN_MODO]  = cb_modo
    _callbacks[cfg.PIN_BTN_RIEGO] = cb_riego
    _callbacks[cfg.PIN_BTN_LUCES] = cb_luces
    _callbacks[cfg.PIN_BTN_RESET] = cb_reset
    threading.Thread(target=_monitorear, daemon=True).start()
    print("[BOTONES] Monitoreo iniciado")


def _monitorear():
    estados = {pin: GPIO.HIGH for pin in _callbacks}
    while _corriendo:
        for pin, callback in _callbacks.items():
            actual = GPIO.input(pin)
            if estados[pin] == GPIO.HIGH and actual == GPIO.LOW:
                print(f"[BOTON] Pin {pin} presionado")
                try:
                    callback()
                except Exception as e:
                    print(f"[BOTON] Error: {e}")
                time.sleep(0.3)
            estados[pin] = actual
        time.sleep(0.05)

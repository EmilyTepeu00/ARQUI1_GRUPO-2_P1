import RPi.GPIO as GPIO
import config_rasp as cfg

GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)

_estado = {
    "bomba":      False,
    "ventilador": False,
    "luces":      False,
    "buzzer":     False,
}


def inicializar():
    salidas = [
        cfg.PIN_RELE_BOMBA, cfg.PIN_RELE_VENT,
        cfg.PIN_LED_LUZ_1,  cfg.PIN_LED_LUZ_2,
        cfg.PIN_BUZZER,
        cfg.PIN_LED_VERDE, cfg.PIN_LED_AMARILLO, cfg.PIN_LED_ROJO,
    ]
    for pin in salidas:
        GPIO.setup(pin, GPIO.OUT)
        GPIO.output(pin, GPIO.LOW)
    print("[ACTUADORES] GPIO inicializado")


def _set(pin, encendido):
    GPIO.output(pin, GPIO.HIGH if encendido else GPIO.LOW)


def bomba(encender):
    _estado["bomba"] = encender
    _set(cfg.PIN_RELE_BOMBA, encender)
    print(f"[ACTUADOR] Bomba -> {'ON' if encender else 'OFF'}")


def apagar_bomba():
    bomba(False)


def ventilador(encender):
    _estado["ventilador"] = encender
    _set(cfg.PIN_RELE_VENT, encender)
    print(f"[ACTUADOR] Ventilador -> {'ON' if encender else 'OFF'}")


def luces(encender):
    _estado["luces"] = encender
    _set(cfg.PIN_LED_LUZ_1, encender)
    _set(cfg.PIN_LED_LUZ_2, encender)
    print(f"[ACTUADOR] Luces -> {'ON' if encender else 'OFF'}")


def buzzer(encender):
    _estado["buzzer"] = encender
    _set(cfg.PIN_BUZZER, encender)
    print(f"[ACTUADOR] Buzzer -> {'ON' if encender else 'OFF'}")


def set_led_estado(estado_global):
    _set(cfg.PIN_LED_VERDE,    False)
    _set(cfg.PIN_LED_AMARILLO, False)
    _set(cfg.PIN_LED_ROJO,     False)

    if estado_global == "NORMAL":
        _set(cfg.PIN_LED_VERDE, True)
    elif estado_global in ("ADVERTENCIA", "RIEGO_ACTIVO", "MODO_MANUAL"):
        _set(cfg.PIN_LED_AMARILLO, True)
    elif estado_global == "EMERGENCIA":
        _set(cfg.PIN_LED_ROJO, True)

    print(f"[LED] -> {estado_global}")


def limpiar():
    apagar_bomba()
    ventilador(False)
    luces(False)
    buzzer(False)
    GPIO.cleanup()
    print("[ACTUADORES] Cleanup OK")


def obtener_estado():
    return _estado.copy()

"""
actuadores.py — Control de actuadores fisicos
Bomba, ventilador, LEDs, buzzer.
Con fallback simulado si no hay GPIO.
"""

try:
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    MODO_REAL = True
except ImportError:
    MODO_REAL = False

import config_rasp as cfg

_estado = {
    "bomba1":     False,
    "bomba2":     False,
    "ventilador": False,
    "luces":      False,
    "buzzer":     False,
    "led_verde":  False,
    "led_amarillo": False,
    "led_rojo":   False,
}


def inicializar():
    if not MODO_REAL:
        print("[ACTUADORES] Modo simulado — sin GPIO")
        return

    salidas = [
        cfg.PIN_BOMBA_1, cfg.PIN_BOMBA_2, cfg.PIN_VENTILADOR,
        cfg.PIN_LED_LUCES_1, cfg.PIN_LED_LUCES_2, cfg.PIN_BUZZER,
        cfg.PIN_LED_VERDE, cfg.PIN_LED_AMARILLO, cfg.PIN_LED_ROJO,
    ]
    for pin in salidas:
        GPIO.setup(pin, GPIO.OUT)
        GPIO.output(pin, GPIO.LOW)

    print("[ACTUADORES] GPIO inicializado")


def _set(pin, encendido):
    if MODO_REAL:
        GPIO.output(pin, GPIO.HIGH if encendido else GPIO.LOW)


# ── Bomba de agua ─────────────────────────────────────────

def bomba_area1(encender):
    _estado["bomba1"] = encender
    _set(cfg.PIN_BOMBA_1, encender)
    print(f"[ACTUADOR] Bomba Area 1 -> {'ON' if encender else 'OFF'}")


def bomba_area2(encender):
    _estado["bomba2"] = encender
    _set(cfg.PIN_BOMBA_2, encender)
    print(f"[ACTUADOR] Bomba Area 2 -> {'ON' if encender else 'OFF'}")


def apagar_bombas():
    bomba_area1(False)
    bomba_area2(False)


# ── Ventilador ────────────────────────────────────────────

def ventilador(encender):
    _estado["ventilador"] = encender
    _set(cfg.PIN_VENTILADOR, encender)
    print(f"[ACTUADOR] Ventilador -> {'ON' if encender else 'OFF'}")


# ── Luces ─────────────────────────────────────────────────

def luces(encender):
    _estado["luces"] = encender
    _set(cfg.PIN_LED_LUCES_1, encender)
    _set(cfg.PIN_LED_LUCES_2, encender)
    print(f"[ACTUADOR] Luces -> {'ON' if encender else 'OFF'}")


# ── Buzzer ────────────────────────────────────────────────

def buzzer(encender):
    _estado["buzzer"] = encender
    _set(cfg.PIN_BUZZER, encender)
    print(f"[ACTUADOR] Buzzer -> {'ON' if encender else 'OFF'}")


# ── LEDs de estado ────────────────────────────────────────

def set_led_estado(estado_global):
    """Enciende el LED correspondiente segun el estado global."""
    _set(cfg.PIN_LED_VERDE,    False)
    _set(cfg.PIN_LED_AMARILLO, False)
    _set(cfg.PIN_LED_ROJO,     False)

    if estado_global == "NORMAL":
        _set(cfg.PIN_LED_VERDE, True)
        print("[LED] Verde (NORMAL)")
    elif estado_global in ("ADVERTENCIA", "RIEGO_ACTIVO", "MODO_MANUAL"):
        _set(cfg.PIN_LED_AMARILLO, True)
        print(f"[LED] Amarillo ({estado_global})")
    elif estado_global == "EMERGENCIA":
        _set(cfg.PIN_LED_ROJO, True)
        print("[LED] Rojo (EMERGENCIA)")


# ── Cleanup ───────────────────────────────────────────────

def limpiar():
    apagar_bombas()
    ventilador(False)
    luces(False)
    buzzer(False)
    if MODO_REAL:
        GPIO.cleanup()
    print("[ACTUADORES] Cleanup OK")


def obtener_estado():
    return _estado.copy()

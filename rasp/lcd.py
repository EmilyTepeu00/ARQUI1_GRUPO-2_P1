"""
lcd.py — Control de pantalla LCD 16x2 via I2C
Con fallback que imprime en consola si no hay hardware.
"""

try:
    from smbus2 import SMBus
    MODO_REAL = True
except ImportError:
    MODO_REAL = False

import config_rasp as cfg
import time

# Comandos LCD
LCD_CHR  = 1
LCD_CMD  = 0
LCD_LINE_1 = 0x80
LCD_LINE_2 = 0xC0
LCD_BACKLIGHT = 0x08
ENABLE = 0b00000100

_bus = None


def inicializar():
    global _bus
    if not MODO_REAL:
        print("[LCD] Modo simulado — salida por consola")
        return
    try:
        _bus = SMBus(1)
        _enviar_byte(0x33, LCD_CMD)
        _enviar_byte(0x32, LCD_CMD)
        _enviar_byte(0x06, LCD_CMD)
        _enviar_byte(0x0C, LCD_CMD)
        _enviar_byte(0x28, LCD_CMD)
        _enviar_byte(0x01, LCD_CMD)
        time.sleep(0.0005)
        print("[LCD] Inicializada OK")
    except Exception as e:
        print(f"[LCD] Error al inicializar: {e}")
        _bus = None


def _enviar_byte(bits, modo):
    if _bus is None:
        return
    bits_high = modo | (bits & 0xF0)       | LCD_BACKLIGHT
    bits_low  = modo | ((bits << 4) & 0xF0)| LCD_BACKLIGHT
    _bus.write_byte(cfg.LCD_ADDRESS, bits_high)
    _toggle_enable(bits_high)
    _bus.write_byte(cfg.LCD_ADDRESS, bits_low)
    _toggle_enable(bits_low)


def _toggle_enable(bits):
    time.sleep(0.0005)
    _bus.write_byte(cfg.LCD_ADDRESS, (bits | ENABLE))
    time.sleep(0.0005)
    _bus.write_byte(cfg.LCD_ADDRESS, (bits & ~ENABLE))
    time.sleep(0.0005)


def limpiar():
    if _bus:
        _enviar_byte(0x01, LCD_CMD)
        time.sleep(0.002)


def escribir(linea1, linea2=""):
    """Escribe dos lineas en el LCD (max 16 chars c/u)."""
    l1 = linea1[:16].ljust(16)
    l2 = linea2[:16].ljust(16)

    if not MODO_REAL or _bus is None:
        print(f"[LCD] |{l1}|")
        print(f"[LCD] |{l2}|")
        return

    _enviar_byte(LCD_LINE_1, LCD_CMD)
    for c in l1:
        _enviar_byte(ord(c), LCD_CHR)

    _enviar_byte(LCD_LINE_2, LCD_CMD)
    for c in l2:
        _enviar_byte(ord(c), LCD_CHR)

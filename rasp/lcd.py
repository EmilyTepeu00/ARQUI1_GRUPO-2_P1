from smbus2 import SMBus
import config_rasp as cfg
import time

LCD_CHR    = 1
LCD_CMD    = 0
LCD_LINE_1 = 0x80
LCD_LINE_2 = 0xC0
LCD_BACKLIGHT = 0x08
ENABLE     = 0b00000100

_bus = None


def inicializar():
    global _bus
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
        print(f"[LCD] Error: {e}")
        _bus = None


def _enviar_byte(bits, modo):
    if _bus is None:
        return
    bits_high = modo | (bits & 0xF0)        | LCD_BACKLIGHT
    bits_low  = modo | ((bits << 4) & 0xF0) | LCD_BACKLIGHT
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
    l1 = linea1[:16].ljust(16)
    l2 = linea2[:16].ljust(16)

    _enviar_byte(LCD_LINE_1, LCD_CMD)
    for c in l1:
        _enviar_byte(ord(c), LCD_CHR)

    _enviar_byte(LCD_LINE_2, LCD_CMD)
    for c in l2:
        _enviar_byte(ord(c), LCD_CHR)

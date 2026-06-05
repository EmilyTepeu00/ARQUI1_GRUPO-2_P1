"""
rasp_main.py — Proceso principal de la Raspberry Pi

Este archivo corre EN LA RASPBERRY PI.
Lee sensores reales (o simulados si no hay GPIO),
controla actuadores, publica por MQTT y maneja botones + LCD.

Arrancar:
    cd invernadero/rasp
    python rasp_main.py
"""

import time
import threading
import signal
import sys
from datetime import datetime

import config_rasp as cfg
import sensores
import actuadores
import lcd
import botones
import mqtt_rasp as mqtt

# ── Estado interno del sistema ─────────────────────────────
estado = {
    "global":     "NORMAL",
    "modo":       "AUTOMATICO",   # AUTOMATICO / MANUAL
    "riego":      "RIEGO_OFF",
    "ventilador": False,
    "luces":      False,
    "alarma":     False,
    "gas":        "GAS_NORMAL",
}

_riego_activo        = False
_tiempo_ultimo_riego = 0
_corriendo           = True

# ── Logica de control automatico ─────────────────────────

def aplicar_control(temp, hum_suelo1, hum_suelo2, luz, gas):
    global _riego_activo, _tiempo_ultimo_riego

    estado_gas    = sensores.clasificar_gas(gas)
    estado_suelo1 = sensores.clasificar_suelo(hum_suelo1)
    estado_suelo2 = sensores.clasificar_suelo(hum_suelo2)

    estado["gas"] = estado_gas

    if estado_gas == "GAS_EMERGENCIA":
        estado["global"]     = "EMERGENCIA"
        estado["ventilador"] = True
        estado["alarma"]     = True
        actuadores.ventilador(True)
        actuadores.buzzer(True)
        actuadores.set_led_estado("EMERGENCIA")
        return estado_suelo1, estado_suelo2

    # Solo control automatico si esta en ese modo
    if estado["modo"] == "AUTOMATICO":

        # Ventilador
        if estado_gas == "GAS_ADVERTENCIA" or temp > cfg.UMBRAL_TEMP_ALTA:
            estado["ventilador"] = True
            actuadores.ventilador(True)
        else:
            estado["ventilador"] = False
            actuadores.ventilador(False)

        # Luces
        if luz < cfg.UMBRAL_LUZ_BAJA:
            estado["luces"] = True
            actuadores.luces(True)
        else:
            estado["luces"] = False
            actuadores.luces(False)

        # Riego — con proteccion anti-riego continuo
        ahora = time.time()
        pausa_ok = (ahora - _tiempo_ultimo_riego) > cfg.PAUSA_ENTRE_RIEGO

        if estado_suelo1 == "SATURADO" or estado_suelo2 == "SATURADO":
            estado["riego"] = "BLOQUEADO_POR_SATURACION"
            actuadores.apagar_bombas()

        elif estado_suelo1 == "SECO" and pausa_ok and not _riego_activo:
            estado["riego"] = "RIEGO_AREA_1"
            _activar_riego(1)

        elif estado_suelo2 == "SECO" and pausa_ok and not _riego_activo:
            estado["riego"] = "RIEGO_AREA_2"
            _activar_riego(2)

        else:
            if not _riego_activo:
                estado["riego"] = "RIEGO_OFF"

    # Estado global
    if _riego_activo:
        estado["global"] = "RIEGO_ACTIVO"
    elif estado["modo"] == "MANUAL":
        estado["global"] = "MODO_MANUAL"
    elif (temp > cfg.UMBRAL_TEMP_ALTA or
          estado_suelo1 == "SECO" or
          estado_suelo2 == "SECO" or
          estado_gas == "GAS_ADVERTENCIA"):
        estado["global"] = "ADVERTENCIA"
    else:
        estado["global"] = "NORMAL"

    actuadores.set_led_estado(estado["global"])
    return estado_suelo1, estado_suelo2


def _activar_riego(area):
    """Activa la bomba por DURACION_RIEGO segundos en un hilo separado."""
    global _riego_activo, _tiempo_ultimo_riego

    def _ciclo():
        global _riego_activo, _tiempo_ultimo_riego
        _riego_activo = True
        print(f"[RIEGO] Iniciando Area {area} por {cfg.DURACION_RIEGO}s")
        if area == 1:
            actuadores.bomba_area1(True)
        else:
            actuadores.bomba_area2(True)
        time.sleep(cfg.DURACION_RIEGO)
        actuadores.apagar_bombas()
        _riego_activo = False
        _tiempo_ultimo_riego = time.time()
        estado["riego"] = "RIEGO_OFF"
        print(f"[RIEGO] Area {area} finalizado")

    threading.Thread(target=_ciclo, daemon=True).start()


# ── LCD rotativa ──────────────────────────────────────────

_lcd_pagina = 0
_lcd_total  = 5
_ultimo_lcd = {}


def actualizar_lcd(temp, hum_aire, hum_suelo1, hum_suelo2, luz, gas,
                   estado_suelo1, estado_suelo2):
    global _lcd_pagina

    # Si hay emergencia la pantalla muestra alerta fija
    if estado["global"] == "EMERGENCIA":
        lcd.escribir("!!! EMERGENCIA !!!", f"GAS: {gas} ppm")
        return

    paginas = [
        (f"Temp: {temp}C",           f"Hum: {hum_aire}%"),
        (f"Suelo1: {hum_suelo1}%",   f"  {estado_suelo1}"),
        (f"Suelo2: {hum_suelo2}%",   f"  {estado_suelo2}"),
        (f"Luz: {luz}",              f"Gas: {gas}"),
        (f"Riego: {estado['riego'][:14]}", f"Est: {estado['global'][:14]}"),
    ]

    linea1, linea2 = paginas[_lcd_pagina % _lcd_total]
    lcd.escribir(linea1, linea2)
    _lcd_pagina += 1


# ── Callbacks de botones ──────────────────────────────────

def btn_modo():
    nuevo = "MANUAL" if estado["modo"] == "AUTOMATICO" else "AUTOMATICO"
    estado["modo"] = nuevo
    print(f"[BTN] Modo -> {nuevo}")
    lcd.escribir(f"Modo: {nuevo[:14]}", "")
    mqtt.publicar_estado_global(estado["global"], estado["modo"])


def btn_riego():
    if estado["modo"] != "MANUAL":
        lcd.escribir("Cambia a MANUAL", "primero")
        return
    if not _riego_activo:
        estado["riego"] = "RIEGO_MANUAL"
        print("[BTN] Riego manual activado")
        _activar_riego(1)


def btn_luces():
    estado["luces"] = not estado["luces"]
    actuadores.luces(estado["luces"])
    print(f"[BTN] Luces -> {'ON' if estado['luces'] else 'OFF'}")


def btn_reset():
    estado["alarma"]  = False
    estado["global"]  = "NORMAL"
    estado["modo"]    = "AUTOMATICO"
    actuadores.buzzer(False)
    actuadores.set_led_estado("NORMAL")
    print("[BTN] Reset / alarma silenciada")
    lcd.escribir("Alarma silenciada", "Modo: AUTO")


# ── Procesar comandos remotos del dashboard ───────────────

def procesar_comando(payload):
    accion = payload.get("accion", "").upper()
    valor  = payload.get("valor",  "").upper()
    print(f"\n[CMD REMOTO] {accion} = {valor}")

    if accion == "RIEGO_AREA1":
        if valor == "ON" and not _riego_activo:
            _activar_riego(1)
        elif valor == "OFF":
            actuadores.bomba_area1(False)

    elif accion == "RIEGO_AREA2":
        if valor == "ON" and not _riego_activo:
            _activar_riego(2)
        elif valor == "OFF":
            actuadores.bomba_area2(False)

    elif accion == "VENTILADOR":
        enc = valor == "ON"
        estado["ventilador"] = enc
        actuadores.ventilador(enc)

    elif accion == "LUCES":
        enc = valor == "ON"
        estado["luces"] = enc
        actuadores.luces(enc)

    elif accion == "ALARMA" and valor == "OFF":
        estado["alarma"] = False
        actuadores.buzzer(False)

    elif accion == "MODO":
        if valor in ("AUTOMATICO", "MANUAL"):
            estado["modo"] = valor

    elif accion == "RESET":
        btn_reset()


# ── Ciclo principal ───────────────────────────────────────

def ciclo():
    print(f"\n{'='*50}")
    print(f"[CICLO] {datetime.now().strftime('%H:%M:%S')}")

    temp, hum_aire = sensores.leer_temperatura_humedad()
    hum_suelo1     = sensores.leer_humedad_suelo(1)
    hum_suelo2     = sensores.leer_humedad_suelo(2)
    luz            = sensores.leer_luz()
    gas            = sensores.leer_gas()

    estado_suelo1 = sensores.clasificar_suelo(hum_suelo1)
    estado_suelo2 = sensores.clasificar_suelo(hum_suelo2)
    estado_gas    = sensores.clasificar_gas(gas)

    print(f"  Temp={temp}C  Hum={hum_aire}%")
    print(f"  Suelo1={hum_suelo1}% ({estado_suelo1})  Suelo2={hum_suelo2}% ({estado_suelo2})")
    print(f"  Luz={luz}  Gas={gas} ({estado_gas})")

    # Control automatico
    aplicar_control(temp, hum_suelo1, hum_suelo2, luz, gas)
    print(f"  Estado={estado['global']}  Modo={estado['modo']}  Riego={estado['riego']}")

    # Publicar por MQTT (el backend recibe y guarda en MongoDB)
    mqtt.publicar_temperatura(temp)
    mqtt.publicar_humedad_ambiente(hum_aire)
    mqtt.publicar_humedad_suelo(1, hum_suelo1, estado_suelo1)
    mqtt.publicar_humedad_suelo(2, hum_suelo2, estado_suelo2)
    mqtt.publicar_luz(luz)
    mqtt.publicar_gas(gas, estado_gas)
    mqtt.publicar_estado_global(estado["global"], estado["modo"])

    # LCD
    actualizar_lcd(temp, hum_aire, hum_suelo1, hum_suelo2,
                   luz, gas, estado_suelo1, estado_suelo2)


def _loop():
    global _corriendo
    print(f"[RASP] Iniciando ciclos cada {cfg.INTERVALO_LECTURA}s")
    while _corriendo:
        try:
            ciclo()
        except Exception as e:
            print(f"[ERROR] {e}")
        time.sleep(cfg.INTERVALO_LECTURA)


def shutdown(sig, frame):
    global _corriendo
    print("\n[RASP] Apagando...")
    _corriendo = False
    actuadores.limpiar()
    mqtt.detener()
    sys.exit(0)


# ── Arranque ──────────────────────────────────────────────

if __name__ == "__main__":
    print("=" * 50)
    print("  INVERNADERO — Raspberry Pi")
    print("=" * 50)

    signal.signal(signal.SIGINT,  shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    sensores.inicializar_gpio_sensores()
    actuadores.inicializar()
    lcd.inicializar()
    botones.inicializar()
    botones.registrar_todos(btn_modo, btn_riego, btn_luces, btn_reset)
    mqtt.iniciar(cb_comando=procesar_comando)

    lcd.escribir("Invernadero IoT", "Iniciando...")
    time.sleep(1)

    _loop()

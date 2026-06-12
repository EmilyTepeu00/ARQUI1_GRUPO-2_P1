"""
rasp_main.py — Programa IoT principal de la Raspberry Pi 4
Lee sensores, controla actuadores, publica por MQTT.
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

estado = {
    "global":     "NORMAL",
    "modo":       "AUTOMATICO",
    "riego":      "RIEGO_OFF",
    "ventilador": False,
    "luces":      False,
    "alarma":     False,
    "gas":        "GAS_NORMAL",
}

_riego_activo        = False
_tiempo_ultimo_riego = 0
_corriendo           = True


def aplicar_control(temp, suelo1, suelo2, luz, gas_valor, gas_estado):
    global _riego_activo, _tiempo_ultimo_riego

    estado["gas"] = gas_estado

    if gas_estado != "GAS_EMERGENCIA" and estado["alarma"]:
        estado["alarma"] = False
        actuadores.buzzer(False)

    if gas_estado == "GAS_EMERGENCIA":
        estado["global"]     = "EMERGENCIA"
        estado["ventilador"] = True
        estado["alarma"]     = True
        actuadores.ventilador(True)
        actuadores.buzzer(True)
        actuadores.set_led_estado("EMERGENCIA")

    if estado["modo"] == "AUTOMATICO":

        if gas_estado == "GAS_ADVERTENCIA" or temp > cfg.UMBRAL_TEMP_ALTA:
            estado["ventilador"] = True
            actuadores.ventilador(True)
        else:
            estado["ventilador"] = False
            actuadores.ventilador(False)

        if luz == "BAJO":
            estado["luces"] = True
            actuadores.luces(True)
        else:
            estado["luces"] = False
            actuadores.luces(False)

        ahora  = time.time()
        pausa_ok = (ahora - _tiempo_ultimo_riego) > cfg.PAUSA_ENTRE_RIEGO

        if suelo1 == "SECO" or suelo2 == "SECO":
            if pausa_ok and not _riego_activo:
                estado["riego"] = "RIEGO_ACTIVO"
                _activar_riego()
        else:
            if not _riego_activo:
                estado["riego"] = "RIEGO_OFF"

    if gas_estado == "GAS_EMERGENCIA":
        estado["global"] = "EMERGENCIA"
    elif _riego_activo:
        estado["global"] = "RIEGO_ACTIVO"
    elif estado["modo"] == "MANUAL":
        estado["global"] = "MODO_MANUAL"
    elif (temp > cfg.UMBRAL_TEMP_ALTA or
          suelo1 == "SECO" or suelo2 == "SECO" or
          gas_estado == "GAS_ADVERTENCIA"):
        estado["global"] = "ADVERTENCIA"
    else:
        estado["global"] = "NORMAL"

    actuadores.set_led_estado(estado["global"])


def _activar_riego():
    global _riego_activo, _tiempo_ultimo_riego

    def _ciclo():
        global _riego_activo, _tiempo_ultimo_riego
        _riego_activo = True
        print(f"[RIEGO] Iniciando por {cfg.DURACION_RIEGO}s")
        actuadores.bomba(True)
        time.sleep(cfg.DURACION_RIEGO)
        actuadores.apagar_bomba()
        _riego_activo = False
        _tiempo_ultimo_riego = time.time()
        estado["riego"] = "RIEGO_OFF"
        print("[RIEGO] Finalizado")

    threading.Thread(target=_ciclo, daemon=True).start()


_lcd_pagina = 0

def actualizar_lcd(temp, hum_aire, suelo1, suelo2, luz, gas_valor, gas_estado):
    global _lcd_pagina

    if estado["global"] == "EMERGENCIA":
        lcd.escribir("!!! EMERGENCIA !!!", f"GAS: {gas_valor}")
        return

    paginas = [
        (f"Temp: {temp}C",          f"Hum: {hum_aire}%"),
        (f"Suelo1: {suelo1}",       f"Suelo2: {suelo2}"),
        (f"Luz: {luz}",             f"Gas: {gas_valor}"),
        (f"Riego: {estado['riego'][:14]}", f"Vent: {'ON' if estado['ventilador'] else 'OFF'}"),
        (f"Luces: {'ON' if estado['luces'] else 'OFF'}", f"Est: {estado['global'][:14]}"),
    ]

    l1, l2 = paginas[_lcd_pagina % len(paginas)]
    lcd.escribir(l1, l2)
    _lcd_pagina += 1


def btn_modo():
    nuevo = "MANUAL" if estado["modo"] == "AUTOMATICO" else "AUTOMATICO"
    estado["modo"] = nuevo
    print(f"[BTN] Modo -> {nuevo}")
    lcd.escribir(f"Modo: {nuevo}", "")
    mqtt.publicar_comando_manual("MODO", nuevo)


def btn_riego():
    if estado["modo"] != "MANUAL":
        lcd.escribir("Cambia a MANUAL", "primero")
        return
    if not _riego_activo:
        estado["riego"] = "RIEGO_MANUAL"
        print("[BTN] Riego manual")
        mqtt.publicar_comando_manual("RIEGO_AREA1", "ON")
        _activar_riego()


def btn_luces():
    estado["luces"] = not estado["luces"]
    actuadores.luces(estado["luces"])
    print(f"[BTN] Luces -> {'ON' if estado['luces'] else 'OFF'}")
    mqtt.publicar_comando_manual("LUCES", "ON" if estado["luces"] else "OFF")

def btn_reset():
    estado["alarma"]  = False
    estado["global"]  = "NORMAL"
    estado["modo"]    = "AUTOMATICO"
    actuadores.buzzer(False)
    actuadores.set_led_estado("NORMAL")
    print("[BTN] Reset — alarma silenciada")
    lcd.escribir("Alarma silenciada", "Modo: AUTO")
    mqtt.publicar_comando_manual("RESET", "")

def procesar_comando(payload):
    accion = payload.get("accion", "").upper()
    valor  = payload.get("valor",  "").upper()
    print(f"\n[CMD REMOTO] {accion} = {valor}")

    if accion == "RIEGO_AREA1" or accion == "RIEGO_AREA2":
        if valor == "ON" and not _riego_activo:
            _activar_riego()
        elif valor == "OFF":
            actuadores.apagar_bomba()

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


def ciclo():
    print(f"\n{'='*50}")
    print(f"[CICLO] {datetime.now().strftime('%H:%M:%S')}")

    temp, hum_aire = sensores.leer_temperatura_humedad()
    valor_suelo1   = sensores.leer_humedad_suelo_valor(1)
    valor_suelo2   = sensores.leer_humedad_suelo_valor(2)
    suelo1         = "SECO" if valor_suelo1 > 800 else "NORMAL"
    suelo2         = "SECO" if valor_suelo2 > 800 else "NORMAL"
    luz            = sensores.leer_luz()
    gas_valor      = sensores.leer_gas()
    gas_estado     = sensores.clasificar_gas(gas_valor)

    print(f"  Temp={temp}C  Hum={hum_aire}%")
    print(f"  Suelo1={suelo1}({valor_suelo1})  Suelo2={suelo2}({valor_suelo2})")
    print(f"  Luz={luz}  Gas={gas_valor} ({gas_estado})")

    aplicar_control(temp, suelo1, suelo2, luz, gas_valor, gas_estado)
    print(f"  Estado={estado['global']}  Modo={estado['modo']}")

    mqtt.publicar_temperatura(temp)
    mqtt.publicar_humedad_ambiente(hum_aire)
    mqtt.publicar_humedad_suelo(1, valor_suelo1, suelo1)
    mqtt.publicar_humedad_suelo(2, valor_suelo2, suelo2)
    mqtt.publicar_luz(luz)
    mqtt.publicar_gas(gas_valor, gas_estado)
    mqtt.publicar_estado_global(estado["global"], estado["modo"])

    actualizar_lcd(temp, hum_aire, suelo1, suelo2, luz, gas_valor, gas_estado)


def _loop():
    global _corriendo
    print(f"[RASP] Ciclos cada {cfg.INTERVALO_LECTURA}s")
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


if __name__ == "__main__":
    print("=" * 50)
    print("  INVERNADERO — Raspberry Pi 4")
    print("=" * 50)

    signal.signal(signal.SIGINT,  shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    sensores.inicializar()
    sensores.inicializar_arduino()
    actuadores.inicializar()
    lcd.inicializar()
    botones.inicializar()
    botones.registrar_todos(btn_modo, btn_riego, btn_luces, btn_reset)
    mqtt.iniciar(cb_comando=procesar_comando)

    lcd.escribir("Invernadero IoT", "Iniciando...")
    time.sleep(1)

    _loop()

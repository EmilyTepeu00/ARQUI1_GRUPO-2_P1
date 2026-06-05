import threading
from datetime import datetime
import config
import database as db

estado_sistema = {
    "global":     "NORMAL",
    "riego":      "RIEGO_OFF",
    "ventilador": "VENTILACION_OFF",
    "luces":      "OFF",
    "alarma":     "OFF",
    "modo":       "AUTOMATICO",
    "gas":        "GAS_NORMAL",
}

_lock = threading.Lock()


def clasificar_suelo(valor):
    if valor < config.UMBRAL_HUMEDAD_BAJA:
        return "SECO"
    elif valor <= config.UMBRAL_HUMEDAD_NORMAL:
        return "NORMAL"
    return "SATURADO"


def clasificar_gas(valor):
    if valor >= config.UMBRAL_GAS_EMERGENCIA:
        return "GAS_EMERGENCIA"
    elif valor >= config.UMBRAL_GAS_ADVERTENCIA:
        return "GAS_ADVERTENCIA"
    return "GAS_NORMAL"


def evaluar_estado_global(temp, hum_suelo1, hum_suelo2):
    with _lock:
        if estado_sistema["gas"] == "GAS_EMERGENCIA":
            return "EMERGENCIA"
        riego_activo = estado_sistema["riego"] not in ("RIEGO_OFF", "BLOQUEADO_POR_SATURACION")
        if riego_activo:
            return "RIEGO_ACTIVO"
        if estado_sistema["modo"] == "MANUAL":
            return "MODO_MANUAL"
        if (temp > config.UMBRAL_TEMP_ALTA or
                hum_suelo1 < config.UMBRAL_HUMEDAD_BAJA or
                hum_suelo2 < config.UMBRAL_HUMEDAD_BAJA):
            return "ADVERTENCIA"
    return "NORMAL"


def decidir_riego(hum_suelo1, hum_suelo2):
    with _lock:
        if estado_sistema["modo"] == "MANUAL":
            return
        estado1 = clasificar_suelo(hum_suelo1)
        estado2 = clasificar_suelo(hum_suelo2)
        if estado1 == "SATURADO" or estado2 == "SATURADO":
            estado_sistema["riego"] = "BLOQUEADO_POR_SATURACION"
        elif estado1 == "SECO":
            estado_sistema["riego"] = "RIEGO_AREA_1"
        elif estado2 == "SECO":
            estado_sistema["riego"] = "RIEGO_AREA_2"
        else:
            estado_sistema["riego"] = "RIEGO_OFF"


def decidir_ventilador(temp):
    with _lock:
        if estado_sistema["gas"] in ("GAS_ADVERTENCIA", "GAS_EMERGENCIA"):
            estado_sistema["ventilador"] = "VENTILACION_EMERGENCIA"
        elif temp > config.UMBRAL_TEMP_ALTA:
            estado_sistema["ventilador"] = "VENTILACION_ON"
        elif estado_sistema["modo"] == "AUTOMATICO":
            estado_sistema["ventilador"] = "VENTILACION_OFF"


def decidir_luces(luz):
    with _lock:
        if estado_sistema["modo"] == "MANUAL":
            return
        estado_sistema["luces"] = "ON" if luz < config.UMBRAL_LUZ_BAJA else "OFF"


def decidir_alarma():
    with _lock:
        if estado_sistema["gas"] == "GAS_EMERGENCIA":
            estado_sistema["alarma"] = "ON"


def aplicar_logica_automatica(lecturas):
    with _lock:
        estado_sistema["gas"] = clasificar_gas(lecturas["gas"])

    if estado_sistema["modo"] == "AUTOMATICO":
        decidir_ventilador(lecturas["temperatura"])
        decidir_luces(lecturas["luz"])
        decidir_riego(lecturas["hum_suelo1"], lecturas["hum_suelo2"])
        decidir_alarma()

    nuevo_global = evaluar_estado_global(
        lecturas["temperatura"], lecturas["hum_suelo1"], lecturas["hum_suelo2"]
    )
    with _lock:
        estado_sistema["global"] = nuevo_global

    db.actualizar_estado_global(estado_sistema.copy())


def procesar_comando(payload, origen="REMOTO"):
    accion = payload.get("accion", "").upper()
    valor  = payload.get("valor",  "").upper()
    ts     = datetime.now().isoformat()

    print(f"[CMD] {accion}={valor} | origen={origen}")

    doc_cmd = {
        "accion":        accion,
        "valor":         valor,
        "origen":        origen,
        "timestamp":     ts,
        "estado_previo": estado_sistema.copy()
    }

    with _lock:
        if accion == "RIEGO_AREA1":
            estado_sistema["riego"] = "RIEGO_AREA_1" if valor == "ON" else "RIEGO_OFF"
        elif accion == "RIEGO_AREA2":
            estado_sistema["riego"] = "RIEGO_AREA_2" if valor == "ON" else "RIEGO_OFF"
        elif accion == "VENTILADOR":
            estado_sistema["ventilador"] = "VENTILACION_MANUAL" if valor == "ON" else "VENTILACION_OFF"
            if valor == "ON":
                estado_sistema["modo"] = "MANUAL"
        elif accion == "LUCES":
            estado_sistema["luces"] = valor
            estado_sistema["modo"]  = "MANUAL"
        elif accion == "ALARMA" and valor == "OFF":
            estado_sistema["alarma"] = "OFF"
        elif accion == "MODO":
            if valor in ("AUTOMATICO", "MANUAL"):
                estado_sistema["modo"] = valor
        elif accion == "RESET":
            estado_sistema["global"]  = "NORMAL"
            estado_sistema["alarma"]  = "OFF"
            estado_sistema["modo"]    = "AUTOMATICO"
        else:
            print(f"[CMD] Accion desconocida: {accion}")

        doc_cmd["estado_nuevo"] = estado_sistema.copy()

    db.guardar(config.COL_COMMANDS, doc_cmd)
    db.actualizar_estado_global(estado_sistema.copy())


def obtener_estado():
    with _lock:
        return estado_sistema.copy()

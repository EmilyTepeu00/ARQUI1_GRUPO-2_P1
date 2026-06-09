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
    if isinstance(valor, str):
        return valor
    # Fallback para valores numericos
    if valor < config.UMBRAL_HUMEDAD_BAJA:
        return "SECO"
    elif valor <= config.UMBRAL_HUMEDAD_NORMAL:
        return "NORMAL"
    return "SATURADO"


def clasificar_gas(valor):
    if isinstance(valor, str):
        return valor
    if valor >= config.UMBRAL_GAS_EMERGENCIA:
        return "GAS_EMERGENCIA"
    elif valor >= config.UMBRAL_GAS_ADVERTENCIA:
        return "GAS_ADVERTENCIA"
    return "GAS_NORMAL"


def evaluar_estado_global(temp, suelo1, suelo2):
    with _lock:
        if estado_sistema["gas"] == "GAS_EMERGENCIA":
            return "EMERGENCIA"
        riego_activo = estado_sistema["riego"] not in ("RIEGO_OFF", "BLOQUEADO_POR_SATURACION")
        if riego_activo:
            return "RIEGO_ACTIVO"
        if estado_sistema["modo"] == "MANUAL":
            return "MODO_MANUAL"
        suelo1_seco = (suelo1 == "SECO") if isinstance(suelo1, str) else (suelo1 < config.UMBRAL_HUMEDAD_BAJA)
        suelo2_seco = (suelo2 == "SECO") if isinstance(suelo2, str) else (suelo2 < config.UMBRAL_HUMEDAD_BAJA)
        if temp > config.UMBRAL_TEMP_ALTA or suelo1_seco or suelo2_seco:
            return "ADVERTENCIA"
    return "NORMAL"


def aplicar_logica_automatica(lecturas):
    with _lock:
        estado_sistema["gas"] = clasificar_gas(lecturas["gas"])

    if estado_sistema["modo"] == "AUTOMATICO":
        temp   = lecturas["temperatura"]
        suelo1 = lecturas["hum_suelo1"]
        suelo2 = lecturas["hum_suelo2"]
        luz    = lecturas.get("luz", "NORMAL")
        gas    = estado_sistema["gas"]

        # Ventilador
        if gas in ("GAS_ADVERTENCIA", "GAS_EMERGENCIA") or temp > config.UMBRAL_TEMP_ALTA:
            estado_sistema["ventilador"] = "VENTILACION_ON"
        else:
            estado_sistema["ventilador"] = "VENTILACION_OFF"

        # Luces
        luz_baja = (luz == "BAJO") if isinstance(luz, str) else (luz < config.UMBRAL_LUZ_BAJA)
        estado_sistema["luces"] = "ON" if luz_baja else "OFF"

        # Riego
        suelo1_seco = (suelo1 == "SECO") if isinstance(suelo1, str) else (suelo1 < config.UMBRAL_HUMEDAD_BAJA)
        suelo2_seco = (suelo2 == "SECO") if isinstance(suelo2, str) else (suelo2 < config.UMBRAL_HUMEDAD_BAJA)
        if suelo1_seco or suelo2_seco:
            estado_sistema["riego"] = "RIEGO_ACTIVO"
        else:
            estado_sistema["riego"] = "RIEGO_OFF"

        # Alarma
        if gas == "GAS_EMERGENCIA":
            estado_sistema["alarma"]     = "ON"
            estado_sistema["ventilador"] = "VENTILACION_EMERGENCIA"

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
        if accion in ("RIEGO_AREA1", "RIEGO_AREA2"):
            estado_sistema["riego"] = "RIEGO_ACTIVO" if valor == "ON" else "RIEGO_OFF"
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

        doc_cmd["estado_nuevo"] = estado_sistema.copy()

    db.guardar(config.COL_COMMANDS, doc_cmd)
    db.actualizar_estado_global(estado_sistema.copy())


def obtener_estado():
    with _lock:
        return estado_sistema.copy()

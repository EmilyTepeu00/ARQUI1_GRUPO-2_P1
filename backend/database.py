# ============================================================
# database.py - Manejo de MongoDB Atlas
# ============================================================

from pymongo import MongoClient
from pymongo.errors import ConnectionFailure
from datetime import datetime
from config import (
    MONGO_URI, MONGO_DB_NAME,
    COL_SENSOR_READINGS, COL_EVENTS, COL_COMMANDS,
    COL_SYSTEM_STATUS, COL_ACTUATOR_LOGS, COL_ARM64_RESULTS
)

_client = None
_db     = None


def iniciar():
    """Conecta a MongoDB Atlas. Retorna True si tuvo exito."""
    global _client, _db
    try:
        _client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
        _client.admin.command("ping")
        _db = _client[MONGO_DB_NAME]
        print(f"[MONGO] Conectado a '{MONGO_DB_NAME}' en Atlas OK")
        return True
    except ConnectionFailure as e:
        print(f"[MONGO] Error de conexion: {e}")
        return False
    except Exception as e:
        print(f"[MONGO] Error inesperado: {e}")
        return False


def cerrar():
    global _client
    if _client:
        _client.close()
        print("[MONGO] Conexion cerrada.")


def guardar(coleccion: str, documento: dict):
    """Inserta un documento en la coleccion indicada."""
    if _db is None:
        print(f"[MONGO] Sin conexion - no se guardo en '{coleccion}'")
        return None
    try:
        resultado = _db[coleccion].insert_one(documento)
        return resultado.inserted_id
    except Exception as e:
        print(f"[MONGO] Error al insertar en '{coleccion}': {e}")
        return None


def obtener_ultimos(coleccion: str, cantidad: int = 20, filtro: dict = None):
    """Retorna los ultimos N documentos de una coleccion."""
    if _db is None:
        return []
    try:
        query = filtro or {}
        cursor = _db[coleccion].find(
            query,
            {"_id": 0}
        ).sort("timestamp", -1).limit(cantidad)
        return list(cursor)
    except Exception as e:
        print(f"[MONGO] Error al consultar '{coleccion}': {e}")
        return []


def obtener_estado_global():
    """Retorna el estado global actual del sistema."""
    if _db is None:
        return {}
    try:
        doc = _db[COL_SYSTEM_STATUS].find_one(
            {"_id": "estado_actual"},
            {"_id": 0}
        )
        return doc or {}
    except Exception as e:
        print(f"[MONGO] Error al obtener estado global: {e}")
        return {}


def actualizar_estado_global(estado: dict):
    """Actualiza (upsert) el estado global en system_status."""
    if _db is None:
        return
    try:
        _db[COL_SYSTEM_STATUS].update_one(
            {"_id": "estado_actual"},
            {"$set": {**estado, "timestamp": datetime.now().isoformat()}},
            upsert=True
        )
    except Exception as e:
        print(f"[MONGO] Error al actualizar estado global: {e}")


def obtener_historial_sensores(limite: int = 30):
    """Retorna las ultimas N lecturas de sensores para graficas."""
    if _db is None:
        return []
    try:
        cursor = _db[COL_SENSOR_READINGS].find(
            {}, {"_id": 0}
        ).sort("timestamp", -1).limit(limite)
        return list(reversed(list(cursor)))
    except Exception as e:
        print(f"[MONGO] Error al obtener historial: {e}")
        return []


def obtener_resultados_arm64():
    """Retorna los resultados de los 5 modulos ARM64."""
    if _db is None:
        return []
    try:
        cursor = _db[COL_ARM64_RESULTS].find(
            {}, {"_id": 0}
        ).sort("timestamp", -1).limit(5)
        return list(cursor)
    except Exception as e:
        print(f"[MONGO] Error al obtener resultados ARM64: {e}")
        return []
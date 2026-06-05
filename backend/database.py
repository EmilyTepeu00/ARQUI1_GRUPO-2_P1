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
    global _client, _db
    try:
        _client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=8000)
        _client.admin.command("ping")
        _db = _client[MONGO_DB_NAME]
        print(f"[MONGO] Conectado a '{MONGO_DB_NAME}' OK")
        return True
    except ConnectionFailure as e:
        print(f"[MONGO] Error de conexion: {e}")
        return False
    except Exception as e:
        print(f"[MONGO] Error: {e}")
        return False


def cerrar():
    global _client
    if _client:
        _client.close()


def guardar(coleccion, documento):
    if _db is None:
        return None
    try:
        return _db[coleccion].insert_one(documento).inserted_id
    except Exception as e:
        print(f"[MONGO] Error insert '{coleccion}': {e}")
        return None


def obtener_ultimos(coleccion, cantidad=20, filtro=None):
    if _db is None:
        return []
    try:
        query = filtro or {}
        cursor = _db[coleccion].find(query, {"_id": 0}).sort("timestamp", -1).limit(cantidad)
        return list(cursor)
    except Exception as e:
        print(f"[MONGO] Error query '{coleccion}': {e}")
        return []


def obtener_estado_global():
    if _db is None:
        return {}
    try:
        doc = _db[COL_SYSTEM_STATUS].find_one({"_id": "estado_actual"}, {"_id": 0})
        return doc or {}
    except Exception:
        return {}


def actualizar_estado_global(estado):
    if _db is None:
        return
    try:
        _db[COL_SYSTEM_STATUS].update_one(
            {"_id": "estado_actual"},
            {"$set": {**estado, "timestamp": datetime.now().isoformat()}},
            upsert=True
        )
    except Exception as e:
        print(f"[MONGO] Error update estado: {e}")


def obtener_historial_sensores(limite=30):
    if _db is None:
        return []
    try:
        cursor = _db[COL_SENSOR_READINGS].find({}, {"_id": 0}).sort("timestamp", -1).limit(limite)
        return list(reversed(list(cursor)))
    except Exception:
        return []


def obtener_resultados_arm64():
    if _db is None:
        return []
    try:
        cursor = _db[COL_ARM64_RESULTS].find({}, {"_id": 0}).sort("timestamp", -1).limit(10)
        return list(cursor)
    except Exception:
        return []

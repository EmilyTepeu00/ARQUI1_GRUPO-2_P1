# ============================================================
# csv_manager.py - Generacion del archivo lecturas.csv
# El archivo es la entrada obligatoria para los modulos ARM64
# ============================================================

import csv
import os
import threading
from datetime import datetime
import config

_lock        = threading.Lock()
_id_counter  = 1
_completo    = False


def inicializar():
    """
    Crea el CSV con encabezados si no existe.
    Si ya existe, retoma el contador desde las filas existentes.
    """
    global _id_counter, _completo

    if not os.path.exists(config.CSV_FILE):
        with open(config.CSV_FILE, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(config.CSV_HEADERS)
        _id_counter = 1
        _completo   = False
        print(f"[CSV] Archivo '{config.CSV_FILE}' creado.")
    else:
        with open(config.CSV_FILE, "r") as f:
            lineas = f.readlines()

        # Contar filas de datos (sin cabecera ni '$')
        filas = [l for l in lineas if l.strip() and
                 not l.startswith("ID") and
                 not l.startswith("$")]
        _id_counter = len(filas) + 1
        _completo   = _id_counter > config.CSV_MAX_ROWS
        print(f"[CSV] Archivo existente — {len(filas)} registros. "
              f"Continuando desde ID {_id_counter}.")


def agregar_fila(temp, hum_aire, hum_suelo1, hum_suelo2,
                 luz, gas, riego1, riego2) -> bool:
    """
    Agrega una fila al CSV.
    Cuando llega a 30 filas agrega el marcador '$' final.
    Retorna True si la fila fue escrita, False si ya esta completo.
    """
    global _id_counter, _completo

    with _lock:
        if _completo:
            return False

        if _id_counter > config.CSV_MAX_ROWS:
            _completo = True
            return False

        fila = [
            _id_counter,
            round(float(temp), 1),
            int(hum_aire),
            int(hum_suelo1),
            int(hum_suelo2),
            int(luz),
            int(gas),
            int(riego1),
            int(riego2),
        ]

        with open(config.CSV_FILE, "a", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(fila)

        print(f"[CSV] Fila {_id_counter}/{config.CSV_MAX_ROWS} -> {fila}")
        _id_counter += 1

        # Al llegar a 30, agregar marcador '$' obligatorio para ARM64
        if _id_counter > config.CSV_MAX_ROWS:
            with open(config.CSV_FILE, "a") as f:
                f.write("$\n")
            _completo = True
            print(f"[CSV] COMPLETO — {config.CSV_MAX_ROWS} registros listos para ARM64.")

        return True


def esta_completo() -> bool:
    return _completo


def obtener_filas() -> int:
    return max(0, _id_counter - 1)


def leer_csv() -> list:
    """Retorna todas las filas del CSV como lista de dicts."""
    if not os.path.exists(config.CSV_FILE):
        return []
    try:
        rows = []
        with open(config.CSV_FILE, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if "$" not in str(row):
                    rows.append(row)
        return rows
    except Exception as e:
        print(f"[CSV] Error al leer: {e}")
        return []
import csv
import os
import threading
import config

_lock       = threading.Lock()
_id_counter = 1
_completo   = False


def inicializar():
    global _id_counter, _completo
    if not os.path.exists(config.CSV_FILE):
        with open(config.CSV_FILE, "w", newline="") as f:
            csv.writer(f).writerow(config.CSV_HEADERS)
        _id_counter = 1
        _completo   = False
        print(f"[CSV] Creado '{config.CSV_FILE}'")
    else:
        with open(config.CSV_FILE, "r") as f:
            lineas = f.readlines()
        filas = [l for l in lineas if l.strip() and not l.startswith("ID") and not l.startswith("$")]
        _id_counter = len(filas) + 1
        _completo   = _id_counter > config.CSV_MAX_ROWS
        print(f"[CSV] Existente — {len(filas)} registros, continuando desde ID {_id_counter}")


def agregar_fila(temp, hum_aire, hum_suelo1, hum_suelo2, luz, gas, riego1, riego2):
    global _id_counter, _completo
    with _lock:
        if _completo or _id_counter > config.CSV_MAX_ROWS:
            _completo = True
            return False
        fila = [_id_counter, round(float(temp),1), int(hum_aire),
                int(hum_suelo1), int(hum_suelo2), int(luz), int(gas),
                int(riego1), int(riego2)]
        with open(config.CSV_FILE, "a", newline="") as f:
            csv.writer(f).writerow(fila)
        print(f"[CSV] Fila {_id_counter}/{config.CSV_MAX_ROWS}")
        _id_counter += 1
        if _id_counter > config.CSV_MAX_ROWS:
            with open(config.CSV_FILE, "a") as f:
                f.write("$\n")
            _completo = True
            print("[CSV] COMPLETO — 30 registros listos para ARM64")
        return True


def esta_completo():
    return _completo


def obtener_filas():
    return max(0, _id_counter - 1)


def leer_csv():
    if not os.path.exists(config.CSV_FILE):
        return []
    try:
        rows = []
        with open(config.CSV_FILE, "r") as f:
            for row in csv.DictReader(f):
                if "$" not in str(row):
                    rows.append(row)
        return rows
    except Exception as e:
        print(f"[CSV] Error al leer: {e}")
        return []

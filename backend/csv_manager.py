import os
import threading
import config

_lock       = threading.Lock()
_id_counter = 1
_completo   = False


def inicializar():
    global _id_counter, _completo
    if not os.path.exists(config.CSV_FILE):
        with open(config.CSV_FILE, "w") as f:
            f.write(",".join(config.CSV_HEADERS) + "\n")
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

        suelo1_num = 0 if hum_suelo1 == "SECO" else 1
        suelo2_num = 0 if hum_suelo2 == "SECO" else 1
        luz_num    = 0 if luz == "BAJO" else 1

        # temp * 10 para evitar punto decimal (24.6 -> 246)
        # ARM64 ascii_a_int no maneja decimales
        valores = [
            str(_id_counter),
            str(int(round(float(temp) * 10))),
            str(int(hum_aire)),
            str(suelo1_num),
            str(suelo2_num),
            str(luz_num),
            str(int(gas)),
            str(int(riego1)),
            str(int(riego2)),
        ]

        with open(config.CSV_FILE, "a") as f:
            f.write(",".join(valores) + "\n")

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
            lineas = f.readlines()
        if not lineas:
            return []
        headers = lineas[0].strip().split(",")
        for linea in lineas[1:]:
            linea = linea.strip()
            if not linea or linea == "$":
                continue
            valores = linea.split(",")
            rows.append(dict(zip(headers, valores)))
        return rows
    except Exception as e:
        print(f"[CSV] Error al leer: {e}")
        return []

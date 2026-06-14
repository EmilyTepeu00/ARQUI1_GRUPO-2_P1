import os
import subprocess
import threading
from datetime import datetime
import database as db
import config

ARM64_DIR      = os.path.join(os.path.dirname(__file__), "..", "ARM64")
RESULTADOS_DIR = ARM64_DIR
CSV_BACKEND    = os.path.join(os.path.dirname(__file__), "lecturas.csv")
CSV_ARM64      = os.path.join(ARM64_DIR, "lecturas.csv")

# Mapeo de nombre de variable -> indice de columna en lecturas.csv
# Cabecera: ID,TEMP,HUM_AIRE,HUM_SUELO_1,HUM_SUELO_2,LUZ,GAS,RIEGO_1,RIEGO_2
#           0   1     2         3            4          5    6     7       8
VARIABLES = {
    "TEMP":        1,
    "HUM_AIRE":    2,
    "HUM_SUELO_1": 3,
    "HUM_SUELO_2": 4,
    "LUZ":         5,
    "GAS":         6,
}

MODULOS = [
    {
        "nombre":  "modulo_1_media",
        "fuente":  "modulo_1_media.s",
        "binario": "modulo_1_media",
        "salida":  "resultado_media.txt",
        "tipo":    "WEIGHTED_MEAN",
    },
    {
        "nombre":  "modulo_2_varianza",
        "fuente":  "modulo_2_varianza.s",
        "binario": "modulo_2_varianza",
        "salida":  "resultado_varianza.txt",
        "tipo":    "VARIANCE",
    },
    {
        "nombre":  "modulo_3_anomalias",
        "fuente":  "modulo_3_anomalias.s",
        "binario": "modulo_3_anomalias",
        "salida":  "resultado_anomalias.txt",
        "tipo":    "ANOMALY_DETECTION",
    },
    {
        "nombre":  "modulo_4_prediccion",
        "fuente":  "modulo_4_prediccion.s",
        "binario": "modulo_4_prediccion",
        "salida":  "resultado_prediccion.txt",
        "tipo":    "PREDICTION",
    },
    {
        "nombre":  "modulo_5_tendecia",
        "fuente":  "modulo_5_tendecia.s",
        "binario": "modulo_5_tendecia",
        "salida":  "resultado_tendencia.txt",
        "tipo":    "ADVANCED_TREND",
    },
]

_ejecutado = False
_lock      = threading.Lock()


def compilar_modulos():
    print("[ARM64] Compilando modulos...")
    utils_o = os.path.join(ARM64_DIR, "utils.o")
    utils_s = os.path.join(ARM64_DIR, "utils.s")

    try:
        r = subprocess.run(
            ["as", utils_s, "-o", utils_o],
            capture_output=True, text=True, cwd=ARM64_DIR
        )
        if r.returncode != 0:
            print(f"[ARM64] Error compilando utils.s: {r.stderr}")
            return False
        print("[ARM64] utils.o OK")
    except FileNotFoundError:
        print("[ARM64] Error: 'as' no encontrado")
        return False

    for m in MODULOS:
        fuente_s = os.path.join(ARM64_DIR, m["fuente"])
        if not os.path.exists(fuente_s):
            print(f"[ARM64] No existe {m['fuente']} — saltando")
            continue

        obj  = os.path.join(ARM64_DIR, m["nombre"] + ".o")
        bin_ = os.path.join(ARM64_DIR, m["binario"])

        r = subprocess.run(
            ["as", fuente_s, "-o", obj],
            capture_output=True, text=True, cwd=ARM64_DIR
        )
        if r.returncode != 0:
            print(f"[ARM64] Error compilando {m['fuente']}: {r.stderr}")
            continue

        r = subprocess.run(
            ["ld", utils_o, obj, "-o", bin_],
            capture_output=True, text=True, cwd=ARM64_DIR
        )
        if r.returncode != 0:
            print(f"[ARM64] Error linkando {m['nombre']}: {r.stderr}")
        else:
            print(f"[ARM64] {m['binario']} compilado OK")

    return True


def ejecutar_modulos(col_index):
    print(f"[ARM64] Ejecutando modulos con columna index={col_index}...")
    col_str = str(col_index)
    for m in MODULOS:
        bin_ = os.path.join(ARM64_DIR, m["binario"])
        if not os.path.exists(bin_):
            print(f"[ARM64] Binario {m['binario']} no existe — saltando")
            continue
        try:
            r = subprocess.run(
                [bin_, col_str],
                capture_output=True, text=True, cwd=ARM64_DIR, timeout=15
            )
            if r.returncode == 0:
                print(f"[ARM64] {m['nombre']} ejecutado OK")
                if r.stdout:
                    print(r.stdout)
            else:
                print(f"[ARM64] {m['nombre']} error (rc={r.returncode}): {r.stderr}")
        except FileNotFoundError:
            print(f"[ARM64] Binario no encontrado: {bin_}")
            break
        except subprocess.TimeoutExpired:
            print(f"[ARM64] Timeout en {m['nombre']}")


def parsear_txt(ruta):
    resultado = {}
    if not os.path.exists(ruta):
        return resultado
    with open(ruta, "r") as f:
        contenido = f.read()
    secciones = contenido.split("---")
    seccion = secciones[0]
    for linea in seccion.strip().splitlines():
        linea = linea.strip()
        if "=" in linea:
            k, v = linea.split("=", 1)
            resultado[k.strip()] = v.strip()
    return resultado


def leer_resultados(variable):
    resultados = []
    for m in MODULOS:
        ruta  = os.path.join(ARM64_DIR, m["salida"])
        datos = parsear_txt(ruta)
        if datos:
            datos["modulo"]    = m["nombre"]
            datos["tipo"]      = m["tipo"]
            datos["variable"]  = variable
            datos["timestamp"] = datetime.now().isoformat()
            resultados.append(datos)
            print(f"[ARM64] Resultado {m['nombre']}: {datos}")
    return resultados


def guardar_en_mongo(resultados):
    for r in resultados:
        db.guardar(config.COL_ARM64_RESULTS, r)
    if resultados:
        print(f"[ARM64] {len(resultados)} resultados guardados en MongoDB")


def _copiar_csv():
    try:
        with open(CSV_BACKEND, "r") as src:
            contenido = src.read()
        if os.path.exists(CSV_ARM64):
            try:
                os.remove(CSV_ARM64)
            except PermissionError:
                pass
        with open(CSV_ARM64, "w") as dst:
            dst.write(contenido)
        print("[ARM64] CSV copiado a ARM64/")
        return CSV_ARM64
    except PermissionError:
        print("[ARM64] Sin permisos para escribir en ARM64/ — los modulos leeran desde backend/")
        return CSV_BACKEND


def correr_pipeline(variable="TEMP"):
    global _ejecutado
    with _lock:
        _ejecutado = True

    import csv_manager
    if not csv_manager.esta_completo():
        print("[ARM64] CSV aun no completo — esperando 30 lecturas")
        return

    variable_upper = variable.upper()
    col_index = VARIABLES.get(variable_upper, 1)
    print(f"[ARM64] Variable seleccionada: {variable_upper} -> columna {col_index}")

    _copiar_csv()

    ok = compilar_modulos()
    if ok:
        ejecutar_modulos(col_index)

    resultados = leer_resultados(variable_upper)
    if resultados:
        guardar_en_mongo(resultados)
    else:
        print("[ARM64] Sin resultados de archivos .txt")


def iniciar_cuando_csv_completo():
    def _monitor():
        import time
        import csv_manager
        while True:
            if csv_manager.esta_completo():
                correr_pipeline()
                break
    t = threading.Thread(target=_monitor, daemon=True)
    t.start()

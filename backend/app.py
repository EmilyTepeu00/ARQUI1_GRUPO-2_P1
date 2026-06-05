# ============================================================
# app.py - Backend Flask del Invernadero Inteligente IoT
# Grupo G2 - ARQUI1
#
# Endpoints disponibles:
#   GET  /                        -> dashboard HTML
#   GET  /api/estado              -> estado global actual
#   GET  /api/sensores/ultimos    -> ultimas N lecturas
#   GET  /api/historial           -> historial para graficas
#   GET  /api/eventos             -> ultimos eventos
#   GET  /api/comandos            -> ultimos comandos
#   GET  /api/arm64               -> resultados modulos ARM64
#   GET  /api/csv                 -> datos del lecturas.csv
#   GET  /api/sistema             -> info del simulador
#   POST /api/comando             -> enviar comando al sistema
#   POST /api/simulador/iniciar   -> iniciar simulador
#   POST /api/simulador/detener   -> detener simulador
# ============================================================

import os
import sys
from flask import Flask, render_template, jsonify, request
from flask_cors import CORS
from datetime import datetime

import config
import database as db
import csv_manager
import simulator
import mqtt_client as mqtt
from state import procesar_comando, obtener_estado

app = Flask(
    __name__,
    template_folder=os.path.join("..", "dashboard", "templates"),
    static_folder=os.path.join("..", "dashboard", "static")
)
CORS(app)


# ============================================================
# RUTAS HTML
# ============================================================

@app.route("/")
def inicio():
    return render_template("index.html")


# ============================================================
# API - ESTADO Y SENSORES
# ============================================================

@app.route("/api/estado")
def api_estado():
    """Estado global actual del sistema."""
    estado = obtener_estado()
    mongo  = db.obtener_estado_global()

    # Ultima lectura de sensores
    ultimas = db.obtener_ultimos(config.COL_SENSOR_READINGS, 1)
    ultima  = ultimas[0] if ultimas else {}

    return jsonify({
        "timestamp":       datetime.now().isoformat(),
        "estado_global":   estado.get("global", "NORMAL"),
        "modo":            estado.get("modo", "AUTOMATICO"),
        "riego":           estado.get("riego", "RIEGO_OFF"),
        "ventilacion":     estado.get("ventilador", "VENTILACION_OFF"),
        "luces":           estado.get("luces", "OFF"),
        "alarma":          estado.get("alarma", "OFF"),
        "temperatura":     ultima.get("temperatura", {}).get("valor", "--"),
        "humedad_ambiente":ultima.get("hum_aire",    {}).get("valor", "--"),
        "suelo_area1":     ultima.get("hum_suelo_1", {}).get("valor", "--"),
        "suelo_area2":     ultima.get("hum_suelo_2", {}).get("valor", "--"),
        "nivel_luz":       ultima.get("luz",         {}).get("valor", "--"),
        "nivel_gas":       ultima.get("gas",         {}).get("valor", "--"),
        "estado_suelo1":   ultima.get("hum_suelo_1", {}).get("estado", "--"),
        "estado_suelo2":   ultima.get("hum_suelo_2", {}).get("estado", "--"),
        "estado_gas":      ultima.get("gas",         {}).get("estado", "--"),
    })


@app.route("/api/sensores/ultimos")
def api_sensores_ultimos():
    """Ultimas N lecturas de sensores."""
    n      = request.args.get("n", 10, type=int)
    datos  = db.obtener_ultimos(config.COL_SENSOR_READINGS, n)
    return jsonify(datos)


@app.route("/api/historial")
def api_historial():
    """
    Historial de sensores para las graficas del dashboard.
    Retorna arrays separados por sensor.
    """
    limite = request.args.get("limite", 30, type=int)
    datos  = db.obtener_historial_sensores(limite)

    historial = {
        "labels":      [],
        "temperatura": [],
        "humedad":     [],
        "suelo1":      [],
        "suelo2":      [],
        "luz":         [],
        "gas":         [],
    }

    for d in datos:
        ts = d.get("timestamp", "")
        historial["labels"].append(ts[11:19] if len(ts) >= 19 else ts)
        historial["temperatura"].append(d.get("temperatura", {}).get("valor", 0))
        historial["humedad"].append(d.get("hum_aire",    {}).get("valor", 0))
        historial["suelo1"].append(d.get("hum_suelo_1", {}).get("valor", 0))
        historial["suelo2"].append(d.get("hum_suelo_2", {}).get("valor", 0))
        historial["luz"].append(d.get("luz",  {}).get("valor", 0))
        historial["gas"].append(d.get("gas",  {}).get("valor", 0))

    return jsonify(historial)


# ============================================================
# API - HISTORIAL Y EVENTOS
# ============================================================

@app.route("/api/eventos")
def api_eventos():
    """Ultimos eventos del sistema."""
    n     = request.args.get("n", 20, type=int)
    datos = db.obtener_ultimos(config.COL_EVENTS, n)
    return jsonify(datos)


@app.route("/api/comandos")
def api_comandos():
    """Ultimos comandos ejecutados."""
    n     = request.args.get("n", 20, type=int)
    datos = db.obtener_ultimos(config.COL_COMMANDS, n)
    return jsonify(datos)


@app.route("/api/actuadores")
def api_actuadores():
    """Historial de activaciones de actuadores."""
    n     = request.args.get("n", 20, type=int)
    datos = db.obtener_ultimos(config.COL_ACTUATOR_LOGS, n)
    return jsonify(datos)


# ============================================================
# API - ARM64
# ============================================================

@app.route("/api/arm64")
def api_arm64():
    """Resultados de los 5 modulos ARM64."""
    datos = db.obtener_resultados_arm64()
    return jsonify(datos)


# ============================================================
# API - CSV
# ============================================================

@app.route("/api/csv")
def api_csv():
    """Informacion y datos del archivo lecturas.csv."""
    return jsonify({
        "completo":  csv_manager.esta_completo(),
        "filas":     csv_manager.obtener_filas(),
        "max_filas": config.CSV_MAX_ROWS,
        "archivo":   config.CSV_FILE,
        "datos":     csv_manager.leer_csv()
    })


# ============================================================
# API - COMANDOS REMOTOS
# ============================================================

@app.route("/api/comando", methods=["POST"])
def api_comando():
    """
    Recibe un comando del dashboard y lo procesa.
    Formato: { "accion": "LUCES", "valor": "ON" }
    """
    datos  = request.get_json()
    if not datos:
        return jsonify({"error": "Body JSON requerido"}), 400

    accion = datos.get("accion", "").upper()
    valor  = datos.get("valor", "").upper()

    if not accion:
        return jsonify({"error": "Campo 'accion' requerido"}), 400

    # Procesar el comando en el estado interno
    procesar_comando({"accion": accion, "valor": valor}, "DASHBOARD")

    # Publicar por MQTT para que la Raspberry Pi lo reciba
    mqtt.publicar_comando_remoto(accion, valor)

    return jsonify({
        "status":    "ok",
        "accion":    accion,
        "valor":     valor,
        "timestamp": datetime.now().isoformat(),
        "estado":    obtener_estado()
    })


# ============================================================
# API - CONTROL DEL SIMULADOR
# ============================================================

@app.route("/api/simulador/iniciar", methods=["POST"])
def api_sim_iniciar():
    """Inicia el simulador de sensores."""
    datos     = request.get_json() or {}
    intervalo = datos.get("intervalo", 15)
    simulator.iniciar(intervalo)
    return jsonify({
        "status":    "iniciado",
        "intervalo": intervalo,
        "timestamp": datetime.now().isoformat()
    })


@app.route("/api/simulador/detener", methods=["POST"])
def api_sim_detener():
    """Detiene el simulador de sensores."""
    simulator.detener()
    return jsonify({
        "status":    "detenido",
        "timestamp": datetime.now().isoformat()
    })


@app.route("/api/sistema")
def api_sistema():
    """Informacion general del sistema."""
    return jsonify({
        "simulador_activo": simulator.esta_corriendo(),
        "csv_completo":     csv_manager.esta_completo(),
        "csv_filas":        csv_manager.obtener_filas(),
        "estado":           obtener_estado(),
        "timestamp":        datetime.now().isoformat()
    })


# ============================================================
# INICIAR APLICACION
# ============================================================

def iniciar_servicios():
    print("=" * 55)
    print("  INVERNADERO INTELIGENTE IoT - Backend")
    print("  Grupo G2 - ARQUI1")
    print("=" * 55)

    # 1. MongoDB
    mongo_ok = db.iniciar()
    if not mongo_ok:
        print("[WARN] Sin MongoDB — los datos no se guardaran.")

    # 2. CSV
    csv_manager.inicializar()

    # 3. MQTT
    mqtt.iniciar()

    # 4. Simulador (inicia automaticamente)
    simulator.iniciar(intervalo=15)

    print("\n[BACKEND] Listo en http://0.0.0.0:5000")
    print("[BACKEND] Dashboard: http://localhost:5000")
    print("[BACKEND] API:       http://localhost:5000/api/estado\n")


if __name__ == "__main__":
    iniciar_servicios()
    app.run(
        host=config.FLASK_HOST,
        port=config.FLASK_PORT,
        debug=False,     # False porque el simulador usa threads
        use_reloader=False
    )
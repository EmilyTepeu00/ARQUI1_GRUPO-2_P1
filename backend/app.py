import os
from flask import Flask, render_template, jsonify, request
from flask_cors import CORS
from datetime import datetime

import config
import database as db
import csv_manager
import mqtt_client as mqtt
import arm64_runner
from state import procesar_comando, obtener_estado

app = Flask(
    __name__,
    template_folder=os.path.join("..", "dashboard", "templates"),
    static_folder=os.path.join("..", "dashboard", "static")
)
CORS(app)


@app.route("/")
def inicio():
    return render_template("index.html")


@app.route("/api/estado")
def api_estado():
    estado  = obtener_estado()
    ultimas = db.obtener_ultimos(config.COL_SENSOR_READINGS, 1)
    ultima  = ultimas[0] if ultimas else {}
    return jsonify({
        "timestamp":        datetime.now().isoformat(),
        "estado_global":    estado.get("global", "NORMAL"),
        "modo":             estado.get("modo", "AUTOMATICO"),
        "riego":            estado.get("riego", "RIEGO_OFF"),
        "ventilacion":      estado.get("ventilador", "VENTILACION_OFF"),
        "luces":            estado.get("luces", "OFF"),
        "alarma":           estado.get("alarma", "OFF"),
        "temperatura":      ultima.get("temperatura", {}).get("valor", "--"),
        "humedad_ambiente": ultima.get("hum_aire",    {}).get("valor", "--"),
        "suelo_area1":      ultima.get("hum_suelo_1", {}).get("valor", "--"),
        "suelo_area2":      ultima.get("hum_suelo_2", {}).get("valor", "--"),
        "nivel_luz":        ultima.get("luz",         {}).get("valor", "--"),
        "nivel_gas":        ultima.get("gas",         {}).get("valor", "--"),
        "estado_suelo1":    ultima.get("hum_suelo_1", {}).get("estado", "--"),
        "estado_suelo2":    ultima.get("hum_suelo_2", {}).get("estado", "--"),
        "estado_gas":       ultima.get("gas",         {}).get("estado", "--"),
    })


@app.route("/api/historial")
def api_historial():
    limite = request.args.get("limite", 30, type=int)
    datos  = db.obtener_historial_sensores(limite)
    h = {"labels":[],"temperatura":[],"humedad":[],"suelo1":[],"suelo2":[],"luz":[],"gas":[]}
    for d in datos:
        ts = d.get("timestamp", "")
        h["labels"].append(ts[11:19] if len(ts) >= 19 else ts)
        h["temperatura"].append(d.get("temperatura", {}).get("valor", 0))
        h["humedad"].append(d.get("hum_aire",    {}).get("valor", 0))
        h["suelo1"].append(d.get("hum_suelo_1", {}).get("valor", 0))
        h["suelo2"].append(d.get("hum_suelo_2", {}).get("valor", 0))
        h["luz"].append(d.get("luz", {}).get("valor", 0))
        h["gas"].append(d.get("gas", {}).get("valor", 0))
    return jsonify(h)


@app.route("/api/eventos")
def api_eventos():
    n = request.args.get("n", 20, type=int)
    return jsonify(db.obtener_ultimos(config.COL_EVENTS, n))


@app.route("/api/comandos")
def api_comandos():
    n = request.args.get("n", 20, type=int)
    return jsonify(db.obtener_ultimos(config.COL_COMMANDS, n))


@app.route("/api/actuadores")
def api_actuadores():
    n = request.args.get("n", 20, type=int)
    return jsonify(db.obtener_ultimos(config.COL_ACTUATOR_LOGS, n))


@app.route("/api/arm64")
def api_arm64():
    return jsonify(db.obtener_resultados_arm64())


@app.route("/api/csv")
def api_csv():
    return jsonify({
        "completo":  csv_manager.esta_completo(),
        "filas":     csv_manager.obtener_filas(),
        "max_filas": config.CSV_MAX_ROWS,
        "datos":     csv_manager.leer_csv()
    })


@app.route("/api/sistema")
def api_sistema():
    return jsonify({
        "csv_completo": csv_manager.esta_completo(),
        "csv_filas":    csv_manager.obtener_filas(),
        "estado":       obtener_estado(),
        "timestamp":    datetime.now().isoformat()
    })


@app.route("/api/comando", methods=["POST"])
def api_comando():
    datos = request.get_json()
    if not datos:
        return jsonify({"error": "Body JSON requerido"}), 400
    accion = datos.get("accion", "").upper()
    valor  = datos.get("valor",  "").upper()
    if not accion:
        return jsonify({"error": "Campo accion requerido"}), 400

    procesar_comando({"accion": accion, "valor": valor}, "DASHBOARD")
    mqtt.publicar_comando_remoto(accion, valor)

    return jsonify({
        "status":    "ok",
        "accion":    accion,
        "valor":     valor,
        "timestamp": datetime.now().isoformat(),
        "estado":    obtener_estado()
    })


@app.route("/api/arm64/ejecutar", methods=["POST"])
def api_arm64_ejecutar():
    import threading
    threading.Thread(target=arm64_runner.correr_pipeline, daemon=True).start()
    return jsonify({"status": "iniciado", "timestamp": datetime.now().isoformat()})


def iniciar_servicios():
    print("=" * 55)
    print("  INVERNADERO INTELIGENTE IoT — Backend")
    print("=" * 55)

    if not db.iniciar():
        print("[WARN] Sin MongoDB — datos no se guardaran")

    csv_manager.inicializar()
    mqtt.iniciar()
    arm64_runner.iniciar_cuando_csv_completo()

    print("[INFO] Esperando datos de la Raspberry Pi por MQTT...")
    print(f"\n[BACKEND] http://localhost:{config.FLASK_PORT}\n")


if __name__ == "__main__":
    iniciar_servicios()
    app.run(host=config.FLASK_HOST, port=config.FLASK_PORT,
            debug=False, use_reloader=False)

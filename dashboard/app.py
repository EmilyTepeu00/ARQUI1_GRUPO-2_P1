from flask import Flask, render_template, jsonify
import random
from datetime import datetime

app = Flask(__name__)

# Datos simulados para pruebas
def generar_datos_mock():
    """Datos simulados"""
    estados = ["NORMAL", "ADVERTENCIA", "EMERGENCIA"]
    estado = random.choice(estados)
    
    # Ajustar valores segun el estado
    if estado == "NORMAL":
        temp = round(random.uniform(20, 28), 1)
        gas = random.randint(50, 150)
        humedad_suelo = random.randint(40, 70)
    elif estado == "ADVERTENCIA":
        temp = round(random.uniform(29, 35), 1)
        gas = random.randint(151, 250)
        humedad_suelo = random.randint(25, 39)
    else:  # EMERGENCIA
        temp = round(random.uniform(36, 45), 1)
        gas = random.randint(251, 500)
        humedad_suelo = random.randint(10, 24)
    
    return {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "estado_global": estado,
        "temperatura": temp,
        "humedad_ambiente": random.randint(40, 85),
        "suelo_area1": random.randint(20, 80),
        "suelo_area2": random.randint(20, 80),
        "nivel_luz": random.randint(100, 800),
        "nivel_gas": gas,
        "riego": random.choice(["INACTIVO", "AREA 1", "AREA 2"]),
        "ventilacion": random.choice(["AUTO", "MANUAL", "OFF"]),
        "luces": random.choice(["ENCENDIDAS", "APAGADAS"]),
        "alarma": "ACTIVA" if estado == "EMERGENCIA" else "SILENCIO"
    }

@app.route("/")
def inicio():
    return render_template("index.html")

@app.route("/api/datos")
def obtener_datos():
    return jsonify(generar_datos_mock())

@app.route("/api/comando", methods=["POST"])
def recibir_comando():
    """Endpoint para recibir comandos del dashboard"""
    return jsonify({"status": "ok", "mensaje": "Comando recibido"})

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
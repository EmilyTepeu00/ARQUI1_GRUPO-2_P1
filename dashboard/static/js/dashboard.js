// CONFIGURACION
const API_URL = "/api/estado";
const API_COMANDO = "/api/comando";

// VARIABLES GLOBALES PARA GRAFICAS
let chartTemperatura, chartHumedad, chartSuelo1, chartSuelo2, chartLuz, chartGas;
let historialDatos = [];

// GENERAR DATOS HISTORICOS MOCK (30 registros para graficas)
function generarHistorial() {
    const datos = [];
    for (let i = 0; i < 30; i++) {
        datos.push({
            temperatura: 20 + Math.random() * 15,
            humedad: 50 + Math.random() * 40,
            suelo1: 30 + Math.random() * 50,
            suelo2: 30 + Math.random() * 50,
            luz: 200 + Math.random() * 600,
            gas: 80 + Math.random() * 250
        });
    }
    return datos;
}

// CREAR TODAS LAS GRAFICAS
function crearGraficas() {
    historialDatos = generarHistorial();
    const labels = Array.from({length: 30}, (_, i) => i + 1);
    
    // GRAFICA TEMPERATURA
    const ctxTemp = document.getElementById('graficoTemperatura').getContext('2d');
    chartTemperatura = new Chart(ctxTemp, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Temperatura',
                data: historialDatos.map(d => d.temperatura),
                borderColor: '#dc3545',
                backgroundColor: 'rgba(220, 53, 69, 0.1)',
                fill: true,
                tension: 0.3
            }]
        },
        options: { responsive: true, maintainAspectRatio: true }
    });
    
    // GRAFICA HUMEDAD AMBIENTAL
    const ctxHum = document.getElementById('graficoHumedad').getContext('2d');
    chartHumedad = new Chart(ctxHum, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Humedad Ambiental',
                data: historialDatos.map(d => d.humedad),
                borderColor: '#17a2b8',
                backgroundColor: 'rgba(23, 162, 184, 0.1)',
                fill: true,
                tension: 0.3
            }]
        },
        options: { responsive: true, maintainAspectRatio: true }
    });
    
    //GRAFICA HUMEDAD DE SUELO AREA 1
    const ctxS1 = document.getElementById('graficoHumedadSuelo1').getContext('2d');
    chartSuelo1 = new Chart(ctxS1, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Humedad de Suelo Area 1',
                data: historialDatos.map(d => d.suelo1),
                borderColor: '#28a745',
                backgroundColor: 'rgba(40, 167, 69, 0.1)',
                fill: true,
                tension: 0.3
            }]
        },
        options: { responsive: true, maintainAspectRatio: true }
    });
    
    // GRAFICA HUMEDAD DE SUELO AREA 2
    const ctxS2 = document.getElementById('graficoHumedadSuelo2').getContext('2d');
    chartSuelo2 = new Chart(ctxS2, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Humedad de Suelo Area 2',
                data: historialDatos.map(d => d.suelo2),
                borderColor: '#ffc107',
                backgroundColor: 'rgba(255, 193, 7, 0.1)',
                fill: true,
                tension: 0.3
            }]
        },
        options: { responsive: true, maintainAspectRatio: true }
    });
    
    // GRAFICA NIVEL DE LUZ
    const ctxLuz = document.getElementById('graficoLuz').getContext('2d');
    chartLuz = new Chart(ctxLuz, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Nivel de Luz',
                data: historialDatos.map(d => d.luz),
                borderColor: '#fd7e14',
                backgroundColor: 'rgba(253, 126, 20, 0.1)',
                fill: true,
                tension: 0.3
            }]
        },
        options: { responsive: true, maintainAspectRatio: true }
    });
    
    // GRAFICA NIVEL DE GAS
    const ctxGas = document.getElementById('graficoGas').getContext('2d');
    chartGas = new Chart(ctxGas, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Nivel de Gas',
                data: historialDatos.map(d => d.gas),
                borderColor: '#dc3545',
                backgroundColor: 'rgba(220, 53, 69, 0.1)',
                fill: true,
                tension: 0.3
            }]
        },
        options: { responsive: true, maintainAspectRatio: true }
    });
}

// ACTUALIZAR DASHBOARD
async function actualizarDashboard() {
    try {
        const response = await fetch(API_URL);
        const data = await response.json();
        
        const estadoDiv = document.getElementById('estadoGlobal');
        estadoDiv.textContent = data.estado_global;
        estadoDiv.className = `estado-display estado-${data.estado_global.toLowerCase()}`;
        
        const mensajes = {
            'NORMAL': 'Sistema operando normalmente',
            'ADVERTENCIA': 'Advertencia: Condiciones fuera del rango optimo',
            'EMERGENCIA': 'Alerta: Condicion critica detectada'
        };
        document.getElementById('estadoMensaje').textContent = mensajes[data.estado_global] || '';
        
        document.getElementById('temperatura').textContent = data.temperatura;
        document.getElementById('humedad').textContent = data.humedad_ambiente;
        document.getElementById('luz').textContent = data.nivel_luz;
        document.getElementById('gas').textContent = data.nivel_gas;
        document.getElementById('suelo1').textContent = data.suelo_area1;
        document.getElementById('suelo2').textContent = data.suelo_area2;
        
        actualizarBarraProgreso('progress1', data.suelo_area1);
        actualizarBarraProgreso('progress2', data.suelo_area2);
        
        actualizarActuador('riego', data.riego);
        actualizarActuador('ventilacion', data.ventilacion);
        actualizarActuador('luces', data.luces);
        actualizarActuador('alarma', data.alarma);
        
    } catch (error) {
        console.error('Error al cargar datos:', error);
    }
}

// BARRA DE PROGRESO
function actualizarBarraProgreso(progressId, valor) {
    const progressBar = document.getElementById(progressId);
    if (progressBar) {
        let color;
        if (valor < 30) color = '#dc3545';
        else if (valor < 50) color = '#ffc107';
        else color = '#28a745';
        progressBar.style.setProperty('--progress-width', `${valor}%`);
        progressBar.style.setProperty('--progress-color', color);
    }
}

// ACTUADOR
function actualizarActuador(id, valor) {
    const elemento = document.getElementById(id);
    if (elemento) {
        elemento.textContent = valor;
        elemento.style.color = '#212529';
        elemento.style.fontWeight = 'normal';
    }
}

// ENVIAR COMANDO
async function enviarComando(comando) {
    const mensajes = {
        'riego_area1': 'Riego Area 1 activado',
        'riego_area2': 'Riego Area 2 activado',
        'luces_on': 'Luces encendidas',
        'luces_off': 'Luces apagadas',
        'ventilador_on': 'Ventilador activado',
        'ventilador_off': 'Ventilador desactivado',
        'modo_auto': 'Modo Automatico activado',
        'modo_manual': 'Modo Manual activado',
        'reset': 'Sistema reiniciado',
        'silenciar': 'Alarma silenciada'
    };
    
    const feedback = document.getElementById('feedback');
    feedback.textContent = mensajes[comando] || comando;
    feedback.style.display = 'block';
    
    setTimeout(() => {
        feedback.style.display = 'none';
    }, 1500);
    
    try {
        await fetch(API_COMANDO, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ comando: comando, timestamp: new Date().toISOString() })
        });
        console.log('Comando enviado:', comando);
    } catch (error) {
        console.error('Error:', error);
    }
}

// EVENTOS SIMULADOS PARA PRUEBAS
const eventosSimulados = [
    { fecha: "2026-06-02 14:30", texto: "Temperatura supero umbral (32°C)", tipo: "alerta" },
    { fecha: "2026-06-02 14:25", texto: "Riego automatico Area 1 activado", tipo: "info" },
    { fecha: "2026-06-02 14:20", texto: "Suelo Area 2 seco (28%)", tipo: "alerta" },
    { fecha: "2026-06-02 14:15", texto: "Luces encendidas por falta de luz", tipo: "info" },
    { fecha: "2026-06-02 14:10", texto: "Ventilacion activada por temperatura alta", tipo: "info" },
    { fecha: "2026-06-02 14:05", texto: "Sistema iniciado correctamente", tipo: "info" }
];

const comandosSimulados = [
    { fecha: "2026-06-02 14:32", texto: "Dashboard → Modo Manual", origen: "dashboard" },
    { fecha: "2026-06-02 14:28", texto: "Boton fisico → Riego Area 2", origen: "fisico" },
    { fecha: "2026-06-02 14:22", texto: "Dashboard → Ventilador ON", origen: "dashboard" },
    { fecha: "2026-06-02 14:18", texto: "Dashboard → Luces ON", origen: "dashboard" },
    { fecha: "2026-06-02 14:15", texto: "Boton fisico → Modo Automatico", origen: "fisico" }
];

// CARGAR HISTORIAL
function cargarHistorial() {
    const eventosContainer = document.getElementById('eventosList');
    const comandosContainer = document.getElementById('comandosList');
    
    if (eventosContainer) {
        eventosContainer.innerHTML = eventosSimulados.map(e => `
            <div class="evento ${e.tipo === 'alerta' ? 'evento-alerta' : ''}">
                <div class="evento-fecha">${e.fecha}</div>
                <div class="evento-texto">${e.texto}</div>
            </div>
        `).join('');
    }
    
    if (comandosContainer) {
        comandosContainer.innerHTML = comandosSimulados.map(c => `
            <div class="evento">
                <div class="evento-fecha">${c.fecha}</div>
                <div class="evento-texto">${c.texto}</div>
                <div class="evento-fecha">Origen: ${c.origen === 'dashboard' ? 'Dashboard' : 'Boton fisico'}</div>
            </div>
        `).join('');
    }
}

// ACTUALIZAR ARM64 (RESULTADOS MOCK)
function actualizarARM64() {
    const resultados = {
        media: 31.2,
        varianza: "Varianza: 18.5 | Std Dev: 4.3",
        anomalias: 3,
        riesgo: "MEDIO",
        prediccion: 34.20,
        tendencia: "UP",
        incrementos: 18,
        rachaMax: 5
    };
    
    document.getElementById('mediaPonderada').innerHTML = resultados.media;
    document.getElementById('varianza').innerHTML = resultados.varianza;
    document.getElementById('anomalias').innerHTML = `${resultados.anomalias} anomalias`;
    
    const riesgoElem = document.getElementById('riesgo');
    riesgoElem.innerHTML = `Riesgo: ${resultados.riesgo}`;
    
    let riesgoClass = 'risk-medio';
    if (resultados.riesgo === 'BAJO') riesgoClass = 'risk-bajo';
    else if (resultados.riesgo === 'ALTO') riesgoClass = 'risk-alto';
    riesgoElem.className = `arm64-risk ${riesgoClass}`;
    
    document.getElementById('prediccion').innerHTML = `Proximo valor: ${resultados.prediccion}`;
    document.getElementById('tendencia').innerHTML = `Tendencia: ${resultados.tendencia} (↑)`;
}

// INICIALIZAR BOTONES
function inicializarBotones() {
    const botones = document.querySelectorAll('[data-comando]');
    botones.forEach(btn => {
        btn.addEventListener('click', () => {
            const comando = btn.getAttribute('data-comando');
            enviarComando(comando);
        });
    });
}

// ESTILOS PROGRESO
function actualizarEstilosProgreso() {
    const style = document.createElement('style');
    style.textContent = `
        .progress-bar::before {
            width: var(--progress-width, 0%);
            background: var(--progress-color, #2e8b57);
        }
    `;
    document.head.appendChild(style);
}

// INICIALIZAR
document.addEventListener('DOMContentLoaded', () => {
    actualizarDashboard();
    cargarHistorial();
    actualizarARM64();
    inicializarBotones();
    actualizarEstilosProgreso();
    crearGraficas();
    setInterval(actualizarDashboard, 3000);
});
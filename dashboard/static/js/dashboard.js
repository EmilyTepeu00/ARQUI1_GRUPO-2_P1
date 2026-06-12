let charts = {};

function mkChart(id, label, color) {
    const ctx = document.getElementById(id).getContext('2d');
    return new Chart(ctx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label,
                data: [],
                borderColor: color,
                backgroundColor: color + '22',
                fill: true,
                tension: 0.3,
                pointRadius: 2
            }]
        },
        options: { responsive: true, maintainAspectRatio: true, animation: false }
    });
}

function initCharts() {
    charts.temp   = mkChart('graficoTemperatura', 'Temperatura',      '#dc3545');
    charts.hum    = mkChart('graficoHumedad',     'Humedad Ambiente', '#17a2b8');
    charts.suelo1 = mkChart('graficoSuelo1',      'Suelo Área 1',     '#28a745');
    charts.suelo2 = mkChart('graficoSuelo2',      'Suelo Área 2',     '#ffc107');
    charts.luz    = mkChart('graficoLuz',          'Luz',             '#fd7e14');
    charts.gas    = mkChart('graficoGas',          'Gas',             '#6f42c1');
}

function updateChart(chart, labels, data) {
    chart.data.labels = labels;
    chart.data.datasets[0].data = data;
    chart.update();
}

const MENSAJES_ESTADO = {
    'NORMAL':       'Sistema operando normalmente',
    'ADVERTENCIA':  'Advertencia: condiciones fuera del rango óptimo',
    'RIEGO_ACTIVO': 'Riego activo',
    'MODO_MANUAL':  'Control manual activado',
    'EMERGENCIA':   '🚨 Alerta crítica detectada'
};

function actualizarBarraProgreso(id, valor) {
    const el = document.getElementById(id);
    if (!el) return;
    el.style.setProperty('--pw', `${valor}%`);
    el.style.setProperty('--pc', valor < 30 ? '#dc3545' : valor < 50 ? '#ffc107' : '#28a745');
}

async function actualizarEstado() {
    try {
        const data = await fetch('/api/estado').then(r => r.json());

        const card = document.getElementById('statusCard');
        const el   = document.getElementById('estadoGlobal');
        el.textContent  = data.estado_global;
        el.className    = `estado-display estado-${data.estado_global.toLowerCase()}`;
        card.className  = `card status-card estado-card-${data.estado_global.toLowerCase()}`;

        document.getElementById('estadoMensaje').textContent = MENSAJES_ESTADO[data.estado_global] || '';
        document.getElementById('modoSistema').textContent   = `Modo: ${data.modo}`;

        document.getElementById('temperatura').textContent = data.temperatura !== '--' ? data.temperatura : '--';
        document.getElementById('humedad').textContent     = data.humedad_ambiente !== '--' ? data.humedad_ambiente : '--';
        document.getElementById('luz').textContent         = data.nivel_luz !== '--' ? data.nivel_luz : '--';
        document.getElementById('gas').textContent         = data.nivel_gas !== '--' ? data.nivel_gas : '--';
        document.getElementById('estadoGas').textContent   = data.estado_gas || '--';

        document.getElementById('suelo1').textContent       = data.suelo_area1 !== '--' ? data.suelo_area1 : '--';
        document.getElementById('suelo2').textContent       = data.suelo_area2 !== '--' ? data.suelo_area2 : '--';
        document.getElementById('estadoSuelo1').textContent = data.estado_suelo1 || '--';
        document.getElementById('estadoSuelo2').textContent = data.estado_suelo2 || '--';

        document.getElementById('riego').textContent      = data.riego;
        document.getElementById('ventilacion').textContent = data.ventilacion;
        document.getElementById('luces').textContent      = data.luces;
        document.getElementById('alarma').textContent     = data.alarma;

        document.getElementById('ultimaActualizacion').textContent =
            'Actualizado: ' + new Date().toLocaleTimeString();
    } catch (e) {
        document.getElementById('ultimaActualizacion').textContent = 'Error de conexión';
    }
}

async function actualizarGraficas() {
    try {
        const h = await fetch('/api/historial?limite=30').then(r => r.json());
        if (!h.labels || h.labels.length === 0) return;
        updateChart(charts.temp,   h.labels, h.temperatura);
        updateChart(charts.hum,    h.labels, h.humedad);
        updateChart(charts.suelo1, h.labels, h.suelo1);
        updateChart(charts.suelo2, h.labels, h.suelo2);
        updateChart(charts.luz,    h.labels, h.luz);
        updateChart(charts.gas,    h.labels, h.gas);
    } catch (e) {}
}

async function actualizarHistorial() {
    try {
        const eventos  = await fetch('/api/eventos?n=10').then(r => r.json());
        const comandos = await fetch('/api/comandos?n=10').then(r => r.json());

        const eEl = document.getElementById('eventosList');
        if (eventos.length === 0) {
            eEl.innerHTML = '<div class="evento"><div class="evento-texto">Sin eventos aún</div></div>';
        } else {
            eEl.innerHTML = eventos.map(e => `
                <div class="evento ${e.estado === 'EMERGENCIA' ? 'evento-emergencia' : e.estado !== 'NORMAL' ? 'evento-alerta' : ''}">
                    <div class="evento-fecha">${(e.timestamp || '').substring(0,19).replace('T',' ')}</div>
                    <div class="evento-texto">${e.estado || ''} — ${e.tipo || ''}</div>
                </div>`).join('');
        }

        const cEl = document.getElementById('comandosList');
        if (comandos.length === 0) {
            cEl.innerHTML = '<div class="evento"><div class="evento-texto">Sin comandos aún</div></div>';
        } else {
            cEl.innerHTML = comandos.map(c => `
                <div class="evento">
                    <div class="evento-fecha">${(c.timestamp || '').substring(0,19).replace('T',' ')}</div>
                    <div class="evento-texto">${c.accion || ''} = ${c.valor || ''}</div>
                    <div class="evento-fecha">Origen: ${c.origen || ''}</div>
                </div>`).join('');
        }
    } catch (e) {}
}

async function actualizarARM64() {
    try {
        const csv = await fetch('/api/csv').then(r => r.json());
        document.getElementById('csvStatus').textContent =
            `CSV: ${csv.filas}/30 lecturas ${csv.completo ? '✅ COMPLETO' : '⏳'}`;

        const datos = await fetch('/api/arm64').then(r => r.json());
        if (!datos || datos.length === 0) return;

        datos.forEach(d => {
            const tipo = d.tipo || d.MODULE;
            if (tipo === 'WEIGHTED_MEAN') {
                document.getElementById('arm64_media').textContent     = `Media Ponderada: ${d.WEIGHTED_MEAN || '--'}`;
                document.getElementById('arm64_media_det').textContent = `Σ(X·W)/ΣW | SumX=${d.SUM_X || '--'} | SumW=${d.WEIGHT_SUM || '--'}`;
            } else if (tipo === 'VARIANCE') {
                document.getElementById('arm64_var').textContent     = `Varianza: ${d.VARIANCE || '--'} | StdDev: ${d.STD_DEV || '--'}`;
                document.getElementById('arm64_var_det').textContent = `Media: ${d.MEAN || '--'} | N=30`;
            } else if (tipo === 'ANOMALY_DETECTION') {
                document.getElementById('arm64_anom').textContent = `${d.ANOMALIES || '--'} anomalías detectadas`;
                const riesgo = d.SYSTEM_RISK || '--';
                const rEl = document.getElementById('arm64_riesgo');
                rEl.textContent = `Riesgo: ${riesgo}`;
                rEl.className = `arm64-risk ${riesgo === 'HIGH' ? 'risk-alto' : riesgo === 'MEDIUM' ? 'risk-medio' : 'risk-bajo'}`;
            } else if (tipo === 'PREDICTION') {
                document.getElementById('arm64_pred').textContent     = `Próximo valor: ${d.NEXT_VALUE || '--'}`;
                document.getElementById('arm64_pred_det').textContent = `Inicial=${d.INITIAL_VALUE || '--'} Final=${d.FINAL_VALUE || '--'} Cambio/ciclo=${d.AVG_CHANGE || '--'}`;
            } else if (tipo === 'ADVANCED_TREND') {
                const flecha = d.TREND === 'UP' ? '↑' : d.TREND === 'DOWN' ? '↓' : '→';
                document.getElementById('arm64_tend').textContent     = `Tendencia: ${d.TREND || '--'} ${flecha}`;
                document.getElementById('arm64_tend_det').textContent = `+${d.INCREMENTS || '--'} incrementos, -${d.DECREMENTS || '--'} decrementos, racha max: ${d.MAX_UP_STREAK || '--'}, diff acum: ${d.ACCUM_DIFF || '--'}`;
            }
        });
    } catch (e) {}
}

async function cmd(accion, valor) {
    try {
        const res = await fetch('/api/comando', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({accion, valor})
        });
        const data = await res.json();
        const fb = document.getElementById('feedback');
        fb.textContent = `✓ ${accion} = ${valor}`;
        fb.style.display = 'block';
        setTimeout(() => { fb.style.display = 'none'; }, 2000);
        actualizarEstado();
    } catch (e) {
        console.error('Error cmd:', e);
    }
}

async function ejecutarARM64() {
    try {
        await fetch('/api/arm64/ejecutar', {method: 'POST'});
        const fb = document.getElementById('feedback');
        fb.textContent = '⚙ Módulos ARM64 iniciados...';
        fb.style.display = 'block';
        setTimeout(() => { fb.style.display = 'none'; actualizarARM64(); }, 3000);
    } catch (e) {}
}

let graficasActualizadas = 0;

async function cicloCompleto() {
    await actualizarEstado();
    graficasActualizadas++;
    if (graficasActualizadas % 2 === 0) await actualizarGraficas();
    if (graficasActualizadas % 4 === 0) await actualizarHistorial();
    if (graficasActualizadas % 6 === 0) await actualizarARM64();
}

document.addEventListener('DOMContentLoaded', () => {
    initCharts();

    const styleEl = document.createElement('style');
    styleEl.textContent = `.progress-bar::before { width: var(--pw,0%); background: var(--pc,#2e8b57); }`;
    document.head.appendChild(styleEl);

    cicloCompleto();
    actualizarGraficas();
    actualizarHistorial();
    actualizarARM64();
    setInterval(cicloCompleto, 4000);
});

// ============================================================
// modulo_3_anomalias.s
// Rutina ARM64 - Deteccion Estadistica de Anomalias
// Proyecto: Invernadero Inteligente IoT - ACYE1
// Integrante 3
//
// Variable analizada: TEMP (columna indice 1)
// Entrada : lecturas.csv (via utils.s)
// Salida  : resultado_anomalias.txt
//
// Compilar:
//   as -o utils.o utils.s
//   as -o modulo_3_anomalias.o modulo_3_anomalias.s
//   ld -o modulo_3_anomalias modulo_3_anomalias.o utils.o
//   ./modulo_3_anomalias
// ============================================================

// ---- Llamadas al sistema ---------------------------------
.equ SYS_OPENAT,  56
.equ SYS_CLOSE,   57
.equ SYS_WRITE,   64
.equ SYS_EXIT,    93
.equ AT_FDCWD,   -100
.equ O_WRONLY,    1
.equ O_CREAT,     64
.equ O_TRUNC,     512
.equ PERM_644,    0644

// ---- Columna objetivo ------------------------------------
.equ COL_OBJETIVO, 1
.equ N_DATOS,      30

// ===========================================================
// SECCION DE DATOS
// ===========================================================
.section .data

archivo_salida:   .asciz "resultado_anomalias.txt"

str_module:       .ascii "MODULE=ANOMALY_DETECTION\n"
.equ str_module_len, . - str_module

str_total:        .ascii "TOTAL_VALUES=30\n"
.equ str_total_len, . - str_total

str_mean_label:   .ascii "MEAN="
.equ str_mean_label_len, . - str_mean_label

str_std_label:    .ascii "STD_DEV="
.equ str_std_label_len, . - str_std_label

str_anom_label:   .ascii "ANOMALIES="
.equ str_anom_label_len, . - str_anom_label

str_risk_label:   .ascii "SYSTEM_RISK="
.equ str_risk_label_len, . - str_risk_label

str_risk_normal:  .ascii "NORMAL\n"
.equ str_risk_normal_len, . - str_risk_normal

str_risk_medium:  .ascii "MEDIUM\n"
.equ str_risk_medium_len, . - str_risk_medium

str_risk_high:    .ascii "HIGH\n"
.equ str_risk_high_len, . - str_risk_high

// ===========================================================
// SECCION BSS
// ===========================================================
.section .bss

buf_conv:      .skip 32
res_mean:      .skip 8
res_std:       .skip 8
res_anomalias: .skip 8

// ===========================================================
// SECCION DE CODIGO
// ===========================================================
.section .text
.global _start

.extern leer_datos
.extern datos

_start:
    // Leer datos usando utils.s
    mov  x0, #COL_OBJETIVO
    bl   leer_datos
    cmp  x0, #N_DATOS
    blt  salir_error

    // calcular media
    // calcular desviacion
    // contar anomalias
    // escribir resultado

    mov  x8,  SYS_EXIT
    mov  x0,  0
    svc  0

salir_error:
    mov  x8,  SYS_EXIT
    mov  x0,  1
    svc  0

// subr_calcular_media
// subr_calcular_desviacion
// subr_raiz_cuadrada
// subr_contar_anomalias
// subr_escribir_resultado
// subr_escribir_buf
// subr_escribir_entero_nl

// ---- Fin modulo_3_anomalias.s -----------------------------
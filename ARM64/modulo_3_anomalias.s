// ============================================================
// modulo_3_anomalias.s
// Rutina ARM64 - Deteccion Estadistica de Anomalias
// Proyecto: Invernadero Inteligente IoT - ACYE1
// Integrante 3
//
// Variable analizada: TEMP (columna indice 6)
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
.equ COL_OBJETIVO, 6
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

    bl  subr_calcular_media
    bl  subr_calcular_desviacion
    bl  subr_contar_anomalias
    bl  subr_escribir_resultado

    mov  x8,  SYS_EXIT
    mov  x0,  0
    svc  0

salir_error:
    mov  x8,  SYS_EXIT
    mov  x0,  1
    svc  0


// ===========================================================
// SUBRUTINA: subr_calcular_media
//
// Calcula la media aritmetica de los 30 datos
// Formula: MEDIA = ΣX / N
// ===========================================================
subr_calcular_media:
    stp  x29, x30, [sp, #-48]!
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    mov  x29, sp

    adr  x19, datos
    mov  x20, #0
    mov  x21, #0

calc_mean_loop:
    cmp  x20, #N_DATOS
    bge  calc_mean_fin

    ldr  x22, [x19, x20, lsl #3]
    add  x21, x21, x22
    add  x20, x20, #1
    b    calc_mean_loop

calc_mean_fin:
    mov  x22, #N_DATOS
    udiv x23, x21, x22

    adr  x9, res_mean
    str  x23, [x9]

    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #48
    ret


// ===========================================================
// SUBRUTINA: subr_calcular_desviacion
//
// Calcula varianza y desviacion estandar
// Formula: VAR = Σ(X - MEDIA)² / N
//          DESV = sqrt(VAR)
// ===========================================================
subr_calcular_desviacion:
    stp  x29, x30, [sp, #-64]!
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    mov  x29, sp

    adr  x19, datos
    adr  x9,  res_mean
    ldr  x21, [x9]
    mov  x20, #0
    mov  x22, #0

calc_var_loop:
    cmp  x20, #N_DATOS
    bge  calc_var_fin

    ldr  x23, [x19, x20, lsl #3]
    sub  x23, x23, x21
    mul  x23, x23, x23
    add  x22, x22, x23

    add  x20, x20, #1
    b    calc_var_loop

calc_var_fin:
    mov  x23, #N_DATOS
    udiv x24, x22, x23

    mov  x0,  x24
    bl   subr_raiz_cuadrada

    adr  x9, res_std
    str  x0,  [x9]

    ldp  x23, x24, [sp, #48]
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #64
    ret


// ===========================================================
// SUBRUTINA: subr_raiz_cuadrada
//
// Metodo de Newton-Raphson para raiz cuadrada entera
// ===========================================================
subr_raiz_cuadrada:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x29, sp

    mov  x19, x0

    cmp  x19, #0
    beq  sqrt_cero

    lsr  x20, x19, #1

    cmp  x20, #0
    beq  sqrt_uno

sqrt_loop:
    udiv x0,  x19, x20
    add  x0,  x0, x20
    lsr  x0,  x0, #1

    cmp  x0, x20
    bge  sqrt_listo

    mov  x20, x0
    b    sqrt_loop

sqrt_listo:
    mov  x0, x20
    b    sqrt_fin

sqrt_cero:
    mov  x0, #0
    b    sqrt_fin

sqrt_uno:
    mov  x0, #1

sqrt_fin:
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret


// ===========================================================
// SUBRUTINA: subr_contar_anomalias
//
// Cuenta datos con |Z| >= 2 donde Z = (X - MEDIA) / DESV
// ===========================================================
subr_contar_anomalias:
    stp  x29, x30, [sp, #-64]!
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    mov  x29, sp

    adr  x19, datos
    adr  x9,  res_mean
    ldr  x21, [x9]
    adr  x9,  res_std
    ldr  x22, [x9]

    mov  x20, #0
    mov  x25, #0

anom_loop:
    cmp  x20, #N_DATOS
    bge  anom_fin

    ldr  x23, [x19, x20, lsl #3]

    sub  x24, x23, x21
    cmp  x24, #0
    bge  anom_positivo
    neg  x24, x24

anom_positivo:
    cmp  x22, #0
    beq  anom_siguiente

    mov  x9,  #10
    mul  x24, x24, x9
    udiv x24, x24, x22

    cmp  x24, #20
    blt  anom_siguiente

    add  x25, x25, #1

anom_siguiente:
    add  x20, x20, #1
    b    anom_loop

anom_fin:
    adr  x9, res_anomalias
    str  x25, [x9]

    ldp  x23, x24, [sp, #48]
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #64
    ret


// ===========================================================
// SUBRUTINA: subr_escribir_resultado
//
// Genera archivo resultado_anomalias.txt
// ===========================================================
subr_escribir_resultado:
    stp  x29, x30, [sp, #-48]!
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    mov  x29, sp

    mov  x8,  SYS_OPENAT
    mov  x0,  AT_FDCWD
    adr  x1,  archivo_salida
    mov  x2,  O_WRONLY | O_CREAT | O_TRUNC
    mov  x3,  PERM_644
    svc  0
    cmp  x0,  0
    blt  er_fin
    mov  x19, x0

    adr  x0, str_module
    mov  x1, str_module_len
    bl   subr_escribir_buf

    adr  x0, str_total
    mov  x1, str_total_len
    bl   subr_escribir_buf

    adr  x0, str_mean_label
    mov  x1, str_mean_label_len
    bl   subr_escribir_buf
    adr  x9, res_mean
    ldr  x0, [x9]
    bl   subr_escribir_entero_nl

    adr  x0, str_std_label
    mov  x1, str_std_label_len
    bl   subr_escribir_buf
    adr  x9, res_std
    ldr  x0, [x9]
    bl   subr_escribir_entero_nl

    adr  x0, str_anom_label
    mov  x1, str_anom_label_len
    bl   subr_escribir_buf
    adr  x9, res_anomalias
    ldr  x0, [x9]
    bl   subr_escribir_entero_nl

    adr  x0, str_risk_label
    mov  x1, str_risk_label_len
    bl   subr_escribir_buf

    adr  x9, res_anomalias
    ldr  x0, [x9]
    cmp  x0, #0
    beq  er_risk_normal
    cmp  x0, #4
    blt  er_risk_medium

er_risk_high:
    adr  x0, str_risk_high
    mov  x1, str_risk_high_len
    bl   subr_escribir_buf
    b    er_cerrar

er_risk_medium:
    adr  x0, str_risk_medium
    mov  x1, str_risk_medium_len
    bl   subr_escribir_buf
    b    er_cerrar

er_risk_normal:
    adr  x0, str_risk_normal
    mov  x1, str_risk_normal_len
    bl   subr_escribir_buf

er_cerrar:
    mov  x8, SYS_CLOSE
    mov  x0, x19
    svc  0

er_fin:
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #48
    ret


// ===========================================================
// SUBRUTINA: subr_escribir_buf
// ===========================================================
subr_escribir_buf:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    mov  x8,  SYS_WRITE
    mov  x2,  x1
    mov  x1,  x0
    mov  x0,  x19
    svc  0

    ldp  x29, x30, [sp], #16
    ret


// ===========================================================
// SUBRUTINA: subr_escribir_entero_nl
// ===========================================================
subr_escribir_entero_nl:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x29, sp

    adr  x9,  buf_conv
    add  x10, x9, #28

    mov  w12, '\n'
    strb w12, [x10]

    cbnz x0, sein_loop
    mov  w12, '0'
    sub  x10, x10, #1
    strb w12, [x10]
    b    sein_escribir

sein_loop:
    cbz  x0, sein_escribir
    mov  x11, #10
    udiv x12, x0, x11
    msub x12, x12, x11, x0
    add  w12, w12, '0'
    sub  x10, x10, #1
    strb w12, [x10]
    udiv x0,  x0, x11
    b    sein_loop

sein_escribir:
    adr  x9, buf_conv
    add  x9, x9, #28
    sub  x1, x9, x10
    add  x1, x1, #1
    mov  x0, x10
    bl   subr_escribir_buf

    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// ---- Fin modulo_3_anomalias.s -----------------------------
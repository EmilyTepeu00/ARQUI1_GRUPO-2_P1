// ============================================================
// modulo_1_media.s
// Rutina ARM64 - Media Aritmetica Ponderada
// Proyecto: Invernadero Inteligente IoT - ACYE1
// Integrante 1
//
// Variable analizada: TEMP (columna indice 1)
// Entrada : lecturas.csv
// Salida  : resultado_media.txt
//
// Formato resultado_media.txt:
//   MODULE=WEIGHTED_MEAN
//   TOTAL_VALUES=30
//   SUM_X=<n>
//   WEIGHT_SUM=465
//   WEIGHTED_MEAN=<n>
//
// Formula:
//   MEDIA_PONDERADA = S(X_i * W_i) / SW_i
//   Donde W_i = 1, 2, 3, ..., 30
//
// Compilar:
//   aarch64-linux-gnu-as utils.s -o utils.o
//   aarch64-linux-gnu-as modulo_1_media.s -o modulo_1_media.o
//   aarch64-linux-gnu-ld utils.o modulo_1_media.o -o modulo_1_media
//
// Ejecutar:
//   qemu-aarch64 ./modulo_1_media
//   cat resultado_media.txt
// ============================================================

// ---- Llamadas al sistema Linux AArch64 --------------------
.equ SYS_OPENAT,  56
.equ SYS_CLOSE,   57
.equ SYS_READ,    63
.equ SYS_WRITE,   64
.equ SYS_EXIT,    93
.equ AT_FDCWD,   -100
.equ O_RDONLY,    0
.equ O_WRONLY,    1
.equ O_CREAT,     64
.equ O_TRUNC,     512
.equ PERM_644,    0644

// ---- Columna objetivo -------------------------------------
.equ COL_OBJETIVO, 1            // TEMP
.equ N_DATOS,      30

// ===========================================================
// SECCION DE DATOS
// ===========================================================
.section .data

archivo_entrada:  .asciz "lecturas.csv"
archivo_salida:   .asciz "resultado_media.txt"

str_module:       .ascii "MODULE=WEIGHTED_MEAN\n"
.equ str_module_len, . - str_module

str_total:        .ascii "TOTAL_VALUES=30\n"
.equ str_total_len, . - str_total

str_sumx_label:   .ascii "SUM_X="
.equ str_sumx_label_len, . - str_sumx_label

str_wsum_label:   .ascii "WEIGHT_SUM="
.equ str_wsum_label_len, . - str_wsum_label

str_mean_label:   .ascii "WEIGHTED_MEAN="
.equ str_mean_label_len, . - str_mean_label

str_newline:      .ascii "\n"

// ===========================================================
// SECCION BSS
// ===========================================================
.section .bss

buf_lectura:   .skip 4096
buf_conv:      .skip 32
arr_datos:     .skip 240        // 30 x 8 bytes
bytes_leidos:  .skip 8

// Resultados
res_sum_x:     .skip 8          // suma simple S(Xi)
res_wsum:      .skip 8          // suma de pesos S(Wi) = 465
res_wpond:     .skip 8          // suma ponderada S(Xi*Wi)
res_mean:      .skip 8          // media ponderada final

// ===========================================================
// SECCION DE CODIGO
// ===========================================================
.section .text
.global _start

// Usar int_a_ascii de utils.s
.extern int_a_ascii

// -----------------------------------------------------------
// _start
// -----------------------------------------------------------
_start:
    // ---------- 1. Abrir lecturas.csv ----------------------
    mov  x8,  SYS_OPENAT
    mov  x0,  AT_FDCWD
    adr  x1,  archivo_entrada
    mov  x2,  O_RDONLY
    mov  x3,  0
    svc  0
    cmp  x0,  0
    blt  salir_error
    mov  x19, x0                // x19 = fd del CSV

    // ---------- 2. Leer todo el archivo --------------------
    mov  x8,  SYS_READ
    mov  x0,  x19
    adr  x1,  buf_lectura
    mov  x2,  4096
    svc  0
    adr  x9,  bytes_leidos
    str  x0,  [x9]

    // ---------- 3. Cerrar archivo --------------------------
    mov  x8,  SYS_CLOSE
    mov  x0,  x19
    svc  0

    // ---------- 4. Parsear CSV -> arr_datos[] --------------
    bl   subr_parsear_csv

    // ---------- 5. Calcular media ponderada ----------------
    bl   subr_calcular_media

    // ---------- 6. Escribir resultado ----------------------
    bl   subr_escribir_resultado

    // ---------- 7. Salir OK --------------------------------
    mov  x8,  SYS_EXIT
    mov  x0,  0
    svc  0

salir_error:
    mov  x8,  SYS_EXIT
    mov  x0,  1
    svc  0


// ===========================================================
// SUBRUTINA: subr_parsear_csv
//
// Lee buf_lectura caracter por caracter.
// Salta la cabecera (primera linea).
// Extrae la columna COL_OBJETIVO de cada fila.
// Guarda los 30 valores en arr_datos[].
//
// Registros:
//   x19 = puntero actual en buf_lectura
//   x20 = puntero al final del buffer
//   x21 = indice de fila (0..29)
//   x22 = columna actual dentro de la fila
//   x23 = acumulador del numero leido
//   x24 = base de arr_datos
//   x25 = byte leido (temporal)
// ===========================================================
subr_parsear_csv:
    stp  x29, x30, [sp, #-80]!
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    stp  x25, x26, [sp, #64]
    mov  x29, sp

    adr  x19, buf_lectura
    adr  x9,  bytes_leidos
    ldr  x9,  [x9]
    add  x20, x19, x9

    adr  x24, arr_datos
    mov  x21, 0

    // Saltar cabecera
pcsv_skip_header:
    cmp  x19, x20
    bge  pcsv_fin
    ldrb w25, [x19], #1
    cmp  w25, '\n'
    bne  pcsv_skip_header

pcsv_fila:
    cmp  x21, N_DATOS
    bge  pcsv_fin
    cmp  x19, x20
    bge  pcsv_fin

    ldrb w25, [x19]
    cmp  w25, '$'
    beq  pcsv_fin

    mov  x22, 0
    mov  x23, 0

pcsv_columna:
    cmp  x19, x20
    bge  pcsv_fin

    ldrb w25, [x19], #1

    cmp  w25, '\r'
    beq  pcsv_columna

    cmp  w25, '\n'
    beq  pcsv_fin_linea

    cmp  w25, ','
    beq  pcsv_separador

    cmp  w25, '0'
    blt  pcsv_columna
    cmp  w25, '9'
    bgt  pcsv_columna

    mov  x9,  10
    mul  x23, x23, x9
    sub  w25, w25, '0'
    add  x23, x23, x25
    b    pcsv_columna

pcsv_separador:
    cmp  x22, COL_OBJETIVO
    beq  pcsv_guardar_valor
    add  x22, x22, 1
    mov  x23, 0
    b    pcsv_columna

pcsv_fin_linea:
    cmp  x22, COL_OBJETIVO
    beq  pcsv_guardar_valor
    add  x21, x21, 1
    b    pcsv_fila

pcsv_guardar_valor:
    str  x23, [x24, x21, lsl #3]
    add  x21, x21, 1

pcsv_skip_resto_fila:
    cmp  x19, x20
    bge  pcsv_fin
    ldrb w25, [x19], #1
    cmp  w25, '\n'
    bne  pcsv_skip_resto_fila
    b    pcsv_fila

pcsv_fin:
    ldp  x25, x26, [sp, #64]
    ldp  x23, x24, [sp, #48]
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #80
    ret


// ===========================================================
// SUBRUTINA: subr_calcular_media
//
// Recorre arr_datos[0..29] y calcula:
//   sum_x  = S(Xi)          suma simple
//   wpond  = S(Xi * Wi)     suma ponderada  Wi = i+1
//   wsum   = S(Wi)          suma de pesos = 465
//   mean   = wpond / wsum   media ponderada
//
// Registros:
//   x19 = base arr_datos
//   x20 = indice i (0..29)
//   x21 = peso Wi (1..30)
//   x22 = acum sum_x
//   x23 = acum wpond
//   x24 = acum wsum
//   x25 = dato[i] temporal
// ===========================================================
subr_calcular_media:
    stp  x29, x30, [sp, #-64]!
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    mov  x29, sp

    adr  x19, arr_datos
    mov  x20, 0             // indice i
    mov  x21, 1             // peso Wi empieza en 1
    mov  x22, 0             // sum_x = 0
    mov  x23, 0             // wpond = 0
    mov  x24, 0             // wsum  = 0

calc_loop:
    cmp  x20, N_DATOS
    bge  calc_fin

    // Cargar dato[i]
    ldr  x25, [x19, x20, lsl #3]

    // sum_x += dato[i]
    add  x22, x22, x25

    // wpond += dato[i] * Wi
    mul  x9,  x25, x21
    add  x23, x23, x9

    // wsum += Wi
    add  x24, x24, x21

    add  x20, x20, 1        // i++
    add  x21, x21, 1        // Wi++
    b    calc_loop

calc_fin:
    // mean = wpond / wsum
    udiv x25, x23, x24

    // Guardar resultados
    adr  x9, res_sum_x
    str  x22, [x9]
    adr  x9, res_wpond
    str  x23, [x9]
    adr  x9, res_wsum
    str  x24, [x9]
    adr  x9, res_mean
    str  x25, [x9]

    ldp  x23, x24, [sp, #48]
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #64
    ret


// ===========================================================
// SUBRUTINA: subr_escribir_resultado
//
// Crea resultado_media.txt y escribe todas las lineas.
// Registros:
//   x19 = fd archivo salida
// ===========================================================
subr_escribir_resultado:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x29, sp

    // Abrir archivo salida
    mov  x8,  SYS_OPENAT
    mov  x0,  AT_FDCWD
    adr  x1,  archivo_salida
    mov  x2,  O_WRONLY | O_CREAT | O_TRUNC
    mov  x3,  PERM_644
    svc  0
    cmp  x0,  0
    blt  er_fin
    mov  x19, x0

    // MODULE=WEIGHTED_MEAN
    adr  x0, str_module
    mov  x1, str_module_len
    bl   subr_escribir_buf

    // TOTAL_VALUES=30
    adr  x0, str_total
    mov  x1, str_total_len
    bl   subr_escribir_buf

    // SUM_X=<valor>
    adr  x0, str_sumx_label
    mov  x1, str_sumx_label_len
    bl   subr_escribir_buf
    adr  x9, res_sum_x
    ldr  x0, [x9]
    bl   subr_escribir_entero_nl

    // WEIGHT_SUM=<valor>
    adr  x0, str_wsum_label
    mov  x1, str_wsum_label_len
    bl   subr_escribir_buf
    adr  x9, res_wsum
    ldr  x0, [x9]
    bl   subr_escribir_entero_nl

    // WEIGHTED_MEAN=<valor>
    adr  x0, str_mean_label
    mov  x1, str_mean_label_len
    bl   subr_escribir_buf
    adr  x9, res_mean
    ldr  x0, [x9]
    bl   subr_escribir_entero_nl

    // Cerrar archivo
    mov  x8, SYS_CLOSE
    mov  x0, x19
    svc  0

er_fin:
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret


// ===========================================================
// SUBRUTINA: subr_escribir_buf
// Escribe x1 bytes desde x0 al fd x19.
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
// Convierte entero en x0 a ASCII y escribe al archivo + \n
// ===========================================================
subr_escribir_entero_nl:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    adr  x9,  buf_conv
    add  x10, x9, #28

    // Poner \n al final
    mov  w12, '\n'
    strb w12, [x10]

    // Caso especial 0
    cbnz x0, sein_loop
    mov  w12, '0'
    sub  x10, x10, #1
    strb w12, [x10]
    b    sein_escribir

sein_loop:
    cbz  x0, sein_escribir
    mov  x11, 10
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

    ldp  x29, x30, [sp], #16
    ret

// ---- Fin modulo_1_media.s ---------------------------------
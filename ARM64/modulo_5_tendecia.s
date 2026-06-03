// ============================================================
// modulo_5_tendencia.s
// Rutina ARM64 - Tendencia Acumulada Avanzada
// Proyecto: Invernadero Inteligente IoT - ACYE1
// Integrante 5
//
// Variables analizadas:
//   - HUM_SUELO_1 (columna indice 3)
//   - HUM_SUELO_2 (columna indice 4)
//
// Entrada : lecturas.csv
// Salida  : resultado_tendencia.txt
//
// Compilar en VM x86:
//   aarch64-linux-gnu-as -o utils.o utils.s
//   aarch64-linux-gnu-as -o modulo_5_tendencia.o modulo_5_tendencia.s
//   aarch64-linux-gnu-ld -o modulo_5_tendencia modulo_5_tendencia.o utils.o
//
// Compilar en Raspberry Pi:
//   as -o utils.o utils.s
//   as -o modulo_5_tendencia.o modulo_5_tendencia.s
//   ld -o modulo_5_tendencia modulo_5_tendencia.o utils.o
//
// Ejecutar:
//   ./modulo_5_tendencia
//   cat resultado_tendencia.txt
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

// ---- Columnas objetivo ------------------------------------
// ID=0, TEMP=1, HUM_AIRE=2, HUM_SUELO_1=3, HUM_SUELO_2=4
.equ COL_SUELO_1,  3
.equ COL_SUELO_2,  4
.equ N_DATOS,      30

// ===========================================================
// SECCION DE DATOS
// ===========================================================
.section .data

archivo_entrada:  .asciz "lecturas.csv"
archivo_salida:   .asciz "resultado_tendencia.txt"

// ---- Etiquetas de salida fijas ----------------------------
str_module:       .ascii "MODULE=ADVANCED_TREND\n"
.equ str_module_len, . - str_module

str_total:        .ascii "TOTAL_VALUES=30\n"
.equ str_total_len, . - str_total

// Separador entre las dos secciones
str_sep:          .ascii "---\n"
.equ str_sep_len, . - str_sep

// Etiquetas HUM_SUELO_1
str_area1:        .ascii "AREA=HUM_SUELO_1\n"
.equ str_area1_len, . - str_area1

// Etiquetas HUM_SUELO_2
str_area2:        .ascii "AREA=HUM_SUELO_2\n"
.equ str_area2_len, . - str_area2

// Etiquetas de valores
str_inc_lbl:      .ascii "INCREMENTS="
.equ str_inc_lbl_len, . - str_inc_lbl

str_dec_lbl:      .ascii "DECREMENTS="
.equ str_dec_lbl_len, . - str_dec_lbl

str_mup_lbl:      .ascii "MAX_UP_STREAK="
.equ str_mup_lbl_len, . - str_mup_lbl

str_mdn_lbl:      .ascii "MAX_DOWN_STREAK="
.equ str_mdn_lbl_len, . - str_mdn_lbl

str_acc_lbl:      .ascii "ACCUM_DIFF="
.equ str_acc_lbl_len, . - str_acc_lbl

str_trend_up:     .ascii "TREND=UP\n"
.equ str_trend_up_len, . - str_trend_up

str_trend_down:   .ascii "TREND=DOWN\n"
.equ str_trend_down_len, . - str_trend_down

str_trend_stable: .ascii "TREND=STABLE\n"
.equ str_trend_stable_len, . - str_trend_stable

str_newline:      .ascii "\n"
str_minus:        .ascii "-"

// ===========================================================
// SECCION BSS
// ===========================================================
.section .bss

buf_csv:          .skip 4096    // buffer para todo el CSV
buf_conv:         .skip 32      // buffer conversion int->ASCII
bytes_leidos:     .skip 8       // bytes leidos del CSV

// Arrays de datos para cada columna
arr_suelo1:       .skip 240     // 30 x 8 bytes HUM_SUELO_1
arr_suelo2:       .skip 240     // 30 x 8 bytes HUM_SUELO_2

// Resultados HUM_SUELO_1
s1_increments:    .skip 8
s1_decrements:    .skip 8
s1_max_up:        .skip 8
s1_max_down:      .skip 8
s1_accum_diff:    .skip 8

// Resultados HUM_SUELO_2
s2_increments:    .skip 8
s2_decrements:    .skip 8
s2_max_up:        .skip 8
s2_max_down:      .skip 8
s2_accum_diff:    .skip 8

// Descriptor archivo salida
fd_out:           .skip 8

// ===========================================================
// SECCION DE CODIGO
// ===========================================================
.section .text
.global _start

// -----------------------------------------------------------
// _start - punto de entrada
// -----------------------------------------------------------
_start:
    // 1. Abrir lecturas.csv
    mov  x8,  SYS_OPENAT
    mov  x0,  AT_FDCWD
    adr  x1,  archivo_entrada
    mov  x2,  O_RDONLY
    mov  x3,  0
    svc  0
    cmp  x0,  0
    blt  salir_error
    mov  x19, x0            // x19 = fd del CSV

    // 2. Leer todo el archivo
    mov  x8,  SYS_READ
    mov  x0,  x19
    adr  x1,  buf_csv
    mov  x2,  4096
    svc  0
    adr  x9,  bytes_leidos
    str  x0,  [x9]

    // 3. Cerrar CSV
    mov  x8,  SYS_CLOSE
    mov  x0,  x19
    svc  0

    // 4. Parsear columna HUM_SUELO_1 -> arr_suelo1
    adr  x0,  arr_suelo1
    mov  x1,  COL_SUELO_1
    bl   subr_parsear_columna

    // 5. Parsear columna HUM_SUELO_2 -> arr_suelo2
    adr  x0,  arr_suelo2
    mov  x1,  COL_SUELO_2
    bl   subr_parsear_columna

    // 6. Calcular tendencia HUM_SUELO_1
    adr  x0,  arr_suelo1
    adr  x1,  s1_increments
    bl   subr_calcular_tendencia

    // 7. Calcular tendencia HUM_SUELO_2
    adr  x0,  arr_suelo2
    adr  x1,  s2_increments
    bl   subr_calcular_tendencia

    // 8. Escribir resultado
    bl   subr_escribir_resultado

    // 9. Salir OK
    mov  x8,  SYS_EXIT
    mov  x0,  0
    svc  0

salir_error:
    mov  x8,  SYS_EXIT
    mov  x0,  1
    svc  0


// ===========================================================
// SUBRUTINA: subr_parsear_columna
//
// Lee buf_csv y extrae la columna indicada en los 30 datos.
//
// Parametros:
//   x0 = puntero al array destino (arr_suelo1 o arr_suelo2)
//   x1 = numero de columna a extraer
//
// Registros:
//   x19 = puntero actual en buf_csv
//   x20 = puntero fin del buffer
//   x21 = indice de fila (0..29)
//   x22 = columna actual
//   x23 = acumulador del numero
//   x24 = array destino
//   x25 = columna objetivo
//   x26 = byte leido
// ===========================================================
subr_parsear_columna:
    stp  x29, x30, [sp, #-80]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    stp  x25, x26, [sp, #64]

    mov  x24, x0            // array destino
    mov  x25, x1            // columna objetivo

    adr  x19, buf_csv
    adr  x9,  bytes_leidos
    ldr  x9,  [x9]
    add  x20, x19, x9       // fin del buffer

    mov  x21, 0             // indice fila = 0

    // Saltar cabecera
spc_skip_header:
    cmp  x19, x20
    bge  spc_fin
    ldrb w26, [x19], #1
    cmp  w26, '\n'
    bne  spc_skip_header

spc_fila:
    cmp  x21, N_DATOS
    bge  spc_fin
    cmp  x19, x20
    bge  spc_fin

    // Verificar '$'
    ldrb w26, [x19]
    cmp  w26, '$'
    beq  spc_fin

    mov  x22, 0             // columna actual = 0
    mov  x23, 0             // acumulador = 0

spc_columna:
    cmp  x19, x20
    bge  spc_fin

    ldrb w26, [x19], #1

    // Ignorar \r
    cmp  w26, '\r'
    beq  spc_columna

    // Fin de linea
    cmp  w26, '\n'
    beq  spc_fin_linea

    // Separador de columna
    cmp  w26, ','
    beq  spc_separador

    // Digito '0'..'9'
    cmp  w26, '0'
    blt  spc_columna
    cmp  w26, '9'
    bgt  spc_columna

    // acum = acum * 10 + digito
    mov  x9,  10
    mul  x23, x23, x9
    sub  w26, w26, '0'
    add  x23, x23, x26
    b    spc_columna

spc_separador:
    cmp  x22, x25
    beq  spc_guardar        // era la columna objetivo
    add  x22, x22, 1
    mov  x23, 0             // resetear acumulador
    b    spc_columna

spc_fin_linea:
    cmp  x22, x25
    beq  spc_guardar_avanzar
    add  x21, x21, 1
    b    spc_fila

spc_guardar:
    str  x23, [x24, x21, lsl #3]
    add  x21, x21, 1
    // Saltar resto de la fila
spc_skip_resto:
    cmp  x19, x20
    bge  spc_fin
    ldrb w26, [x19], #1
    cmp  w26, '\n'
    bne  spc_skip_resto
    b    spc_fila

spc_guardar_avanzar:
    str  x23, [x24, x21, lsl #3]
    add  x21, x21, 1
    b    spc_fila

spc_fin:
    ldp  x25, x26, [sp, #64]
    ldp  x23, x24, [sp, #48]
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #80
    ret



subr_calcular_tendencia:
    stp  x29, x30, [sp, #-96]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    stp  x25, x26, [sp, #64]
    stp  x27, x28, [sp, #80]

    mov  x19, x0            // array de datos
    mov  x20, x1            // bloque de resultados

    mov  x21, 1             // i = 1
    mov  x22, 0             // incrementos
    mov  x23, 0             // decrementos
    mov  x24, 0             // racha_up actual
    mov  x25, 0             // racha_down actual
    mov  x26, 0             // max_up
    mov  x27, 0             // max_down
    mov  x28, 0             // accum_diff

sct_loop:
    cmp  x21, N_DATOS
    bge  sct_fin

    // dato[i-1]
    sub  x9,  x21, 1
    ldr  x10, [x19, x9,  lsl #3]
    // dato[i]
    ldr  x9,  [x19, x21, lsl #3]

    // DIF_i = dato[i] - dato[i-1]
    sub  x11, x9, x10
    add  x28, x28, x11      // accum_diff += DIF_i

    cmp  x11, 0
    bgt  sct_incremento
    blt  sct_decremento

    // Igual: resetear rachas
    mov  x24, 0
    mov  x25, 0
    b    sct_siguiente

sct_incremento:
    add  x22, x22, 1        // incrementos++
    add  x24, x24, 1        // racha_up++
    mov  x25, 0             // resetear racha_down
    cmp  x24, x26
    ble  sct_siguiente
    mov  x26, x24           // actualizar max_up
    b    sct_siguiente

sct_decremento:
    add  x23, x23, 1        // decrementos++
    add  x25, x25, 1        // racha_down++
    mov  x24, 0             // resetear racha_up
    cmp  x25, x27
    ble  sct_siguiente
    mov  x27, x25           // actualizar max_down

sct_siguiente:
    add  x21, x21, 1
    b    sct_loop

sct_fin:
    // Guardar resultados en el bloque
    str  x22, [x20, #0]     // increments
    str  x23, [x20, #8]     // decrements
    str  x26, [x20, #16]    // max_up
    str  x27, [x20, #24]    // max_down
    str  x28, [x20, #32]    // accum_diff

    ldp  x27, x28, [sp, #80]
    ldp  x25, x26, [sp, #64]
    ldp  x23, x24, [sp, #48]
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #96
    ret


// ===========================================================
// SUBRUTINA: subr_escribir_resultado
//
// Crea resultado_tendencia.txt y escribe los resultados
// de HUM_SUELO_1 y HUM_SUELO_2.
// ===========================================================
subr_escribir_resultado:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x29, sp

    // Abrir archivo de salida
    mov  x8,  SYS_OPENAT
    mov  x0,  AT_FDCWD
    adr  x1,  archivo_salida
    mov  x2,  O_WRONLY | O_CREAT | O_TRUNC
    mov  x3,  PERM_644
    svc  0
    cmp  x0,  0
    blt  ser_fin
    mov  x19, x0            // x19 = fd salida

    // MODULE=ADVANCED_TREND
    adr  x0,  str_module
    mov  x1,  str_module_len
    bl   ser_write

    // TOTAL_VALUES=30
    adr  x0,  str_total
    mov  x1,  str_total_len
    bl   ser_write

    // ---- Seccion HUM_SUELO_1 ------------------------------
    adr  x0,  str_area1
    mov  x1,  str_area1_len
    bl   ser_write

    adr  x20, s1_increments
    bl   ser_escribir_bloque

    // Separador
    adr  x0,  str_sep
    mov  x1,  str_sep_len
    bl   ser_write

    // ---- Seccion HUM_SUELO_2 ------------------------------
    adr  x0,  str_area2
    mov  x1,  str_area2_len
    bl   ser_write

    adr  x20, s2_increments
    bl   ser_escribir_bloque

    // Cerrar archivo
    mov  x8,  SYS_CLOSE
    mov  x0,  x19
    svc  0

ser_fin:
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret


// ===========================================================
// SUBRUTINA INTERNA: ser_escribir_bloque
// Escribe los 5 campos de un bloque de resultados.
// x20 = puntero al bloque (increments, decrements, max_up,
//        max_down, accum_diff)
// x19 = fd salida (ya abierto)
// ===========================================================
ser_escribir_bloque:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    // INCREMENTS=
    adr  x0,  str_inc_lbl
    mov  x1,  str_inc_lbl_len
    bl   ser_write
    ldr  x0,  [x20, #0]
    bl   ser_escribir_uint_nl

    // DECREMENTS=
    adr  x0,  str_dec_lbl
    mov  x1,  str_dec_lbl_len
    bl   ser_write
    ldr  x0,  [x20, #8]
    bl   ser_escribir_uint_nl

    // MAX_UP_STREAK=
    adr  x0,  str_mup_lbl
    mov  x1,  str_mup_lbl_len
    bl   ser_write
    ldr  x0,  [x20, #16]
    bl   ser_escribir_uint_nl

    // MAX_DOWN_STREAK=
    adr  x0,  str_mdn_lbl
    mov  x1,  str_mdn_lbl_len
    bl   ser_write
    ldr  x0,  [x20, #24]
    bl   ser_escribir_uint_nl

    // ACCUM_DIFF= (puede ser negativo)
    adr  x0,  str_acc_lbl
    mov  x1,  str_acc_lbl_len
    bl   ser_write
    ldr  x0,  [x20, #32]
    bl   ser_escribir_int_nl

    // TREND=
    ldr  x0,  [x20, #32]
    cmp  x0,  0
    bgt  seb_up
    blt  seb_down
    adr  x0,  str_trend_stable
    mov  x1,  str_trend_stable_len
    bl   ser_write
    b    seb_fin
seb_up:
    adr  x0,  str_trend_up
    mov  x1,  str_trend_up_len
    bl   ser_write
    b    seb_fin
seb_down:
    adr  x0,  str_trend_down
    mov  x1,  str_trend_down_len
    bl   ser_write
seb_fin:
    ldp  x29, x30, [sp], #16
    ret


// ===========================================================
// ser_write - escribe x1 bytes desde x0 al fd x19
// ===========================================================
ser_write:
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
// ser_escribir_uint_nl
// Convierte x0 (entero sin signo) a ASCII y escribe + '\n'
// ===========================================================
ser_escribir_uint_nl:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    adr  x9,  buf_conv
    add  x10, x9, #28       // cursor al final
    mov  w11, '\n'
    strb w11, [x10]         // poner \n al final

    cbnz x0,  seun_loop
    mov  w11, '0'
    sub  x10, x10, #1
    strb w11, [x10]
    b    seun_write

seun_loop:
    cbz  x0,  seun_write
    mov  x12, 10
    udiv x13, x0, x12
    msub x13, x13, x12, x0
    add  w13, w13, '0'
    sub  x10, x10, #1
    strb w13, [x10]
    udiv x0,  x0, x12
    b    seun_loop

seun_write:
    adr  x9,  buf_conv
    add  x9,  x9, #28
    sub  x1,  x9, x10
    add  x1,  x1, #1        // +1 por el \n
    mov  x0,  x10
    bl   ser_write

    ldp  x29, x30, [sp], #16
    ret


// ===========================================================
// ser_escribir_int_nl
// Igual que ser_escribir_uint_nl pero maneja negativos.
// ===========================================================
ser_escribir_int_nl:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x29, sp

    cmp  x0,  0
    bge  sein_positivo

    // Escribir '-'
    mov  x20, x0
    neg  x20, x20           // valor absoluto
    mov  x8,  SYS_WRITE
    mov  x0,  x19
    adr  x1,  str_minus
    mov  x2,  1
    svc  0
    mov  x0,  x20

sein_positivo:
    bl   ser_escribir_uint_nl

    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// ---- Fin del archivo --------------------------------------
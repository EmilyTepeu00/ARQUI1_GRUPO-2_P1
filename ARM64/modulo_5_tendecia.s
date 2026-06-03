// ============================================================
// modulo_5_tendencia.s
// Rutina ARM64 - Tendencia Acumulada Avanzada
// Proyecto: Invernadero Inteligente IoT - ACYE1
// Integrante 5
//
// Variable analizada: HUM_SUELO_1 (columna indice 3)
// Entrada : lecturas.csv
// Salida  : resultado_tendencia.txt
//
// Formato esperado resultado_tendencia.txt:
//   MODULE=ADVANCED_TREND
//   TOTAL_VALUES=30
//   INCREMENTS=<n>
//   DECREMENTS=<n>
//   MAX_UP_STREAK=<n>
//   MAX_DOWN_STREAK=<n>
//   ACCUM_DIFF=<n>
//   TREND=UP | DOWN | STABLE
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

// ---- Columna objetivo -------------------------------------
// ID=0, TEMP=1, HUM_AIRE=2, HUM_SUELO_1=3, HUM_SUELO_2=4
// LUZ=5, GAS=6, RIEGO_1=7, RIEGO_2=8
.equ COL_OBJETIVO, 3            // HUM_SUELO_1
.equ N_DATOS,      30           // exactamente 30 lecturas

// ===========================================================
// SECCION DE DATOS
// ===========================================================
.section .data

// Nombres de archivos
archivo_entrada:  .asciz "lecturas.csv"
archivo_salida:   .asciz "resultado_tendencia.txt"

// Lineas fijas de salida
str_module:       .ascii "MODULE=ADVANCED_TREND\n"
.equ str_module_len, . - str_module

str_total:        .ascii "TOTAL_VALUES=30\n"
.equ str_total_len, . - str_total

str_inc_label:    .ascii "INCREMENTS="
.equ str_inc_label_len, . - str_inc_label

str_dec_label:    .ascii "DECREMENTS="
.equ str_dec_label_len, . - str_dec_label

str_mup_label:    .ascii "MAX_UP_STREAK="
.equ str_mup_label_len, . - str_mup_label

str_mdn_label:    .ascii "MAX_DOWN_STREAK="
.equ str_mdn_label_len, . - str_mdn_label

str_acc_label:    .ascii "ACCUM_DIFF="
.equ str_acc_label_len, . - str_acc_label

str_trend_up:     .ascii "TREND=UP\n"
.equ str_trend_up_len, . - str_trend_up

str_trend_down:   .ascii "TREND=DOWN\n"
.equ str_trend_down_len, . - str_trend_down

str_trend_stable: .ascii "TREND=STABLE\n"
.equ str_trend_stable_len, . - str_trend_stable

str_newline:      .ascii "\n"
str_minus:        .ascii "-"

// ===========================================================
// SECCION BSS  (variables sin inicializar)
// ===========================================================
.section .bss

buf_lectura:   .skip 4096       // buffer para leer el CSV completo
buf_conv:      .skip 32         // buffer para conversion int->ASCII
arr_datos:     .skip 240        // 30 enteros x 8 bytes = 240 bytes
bytes_leidos:  .skip 8          // cuantos bytes leyo SYS_READ
fd_salida:     .skip 8          // descriptor del archivo de salida

// Variables resultado
res_increments:    .skip 8
res_decrements:    .skip 8
res_max_up:        .skip 8
res_max_down:      .skip 8
res_accum_diff:    .skip 8

// ===========================================================
// SECCION DE CODIGO
// ===========================================================
.section .text
.global _start

// -----------------------------------------------------------
// _start
// Punto de entrada. Orquesta: abrir -> leer -> parsear ->
// calcular -> escribir resultado -> salir.
// -----------------------------------------------------------
_start:
    // ---------- 1. Abrir lecturas.csv ----------------------
    mov  x8,  SYS_OPENAT
    mov  x0,  AT_FDCWD
    adr  x1,  archivo_entrada
    mov  x2,  O_RDONLY
    mov  x3,  0
    svc  0
    // Si x0 < 0 hubo error
    cmp  x0,  0
    blt  salir_error
    mov  x19, x0                // x19 = fd del CSV

    // ---------- 2. Leer todo el archivo --------------------
    mov  x8,  SYS_READ
    mov  x0,  x19
    adr  x1,  buf_lectura
    mov  x2,  4096
    svc  0
    // Guardar cuantos bytes leyo
    adr  x9,  bytes_leidos
    str  x0,  [x9]

    // ---------- 3. Cerrar el archivo -----------------------
    mov  x8,  SYS_CLOSE
    mov  x0,  x19
    svc  0

    // ---------- 4. Parsear CSV -> arr_datos[] --------------
    bl   subr_parsear_csv

    // ---------- 5. Calcular tendencia ----------------------
    bl   subr_calcular_tendencia

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
// Recorre buf_lectura caracter por caracter.
// Salta la primera linea (cabecera).
// En cada fila, cuenta columnas separadas por coma.
// Cuando llega a la columna COL_OBJETIVO (3 = HUM_SUELO_1),
// convierte el texto ASCII a entero y lo guarda en arr_datos.
// Para cuando llega a 30 datos o encuentra '$'.
//
// Registros utilizados:
//   x19 = puntero actual dentro de buf_lectura
//   x20 = puntero al final del buffer (inicio + bytes_leidos)
//   x21 = indice de fila actual (0..29)
//   x22 = columna actual dentro de la fila
//   x23 = acumulador del numero que se esta leyendo
//   x24 = puntero base de arr_datos
//   x25 = byte leido (temporal)
// ===========================================================
subr_parsear_csv:
    // Guardar registros en el stack
    stp  x29, x30, [sp, #-80]!
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    stp  x25, x26, [sp, #64]
    mov  x29, sp

    // Inicializar punteros
    adr  x19, buf_lectura
    adr  x9,  bytes_leidos
    ldr  x9,  [x9]
    add  x20, x19, x9           // x20 = fin del buffer

    adr  x24, arr_datos         // base del array de resultados
    mov  x21, 0                 // indice de fila = 0

    // ---- Saltar cabecera (primera linea hasta \n) ----------
pcsv_skip_header:
    cmp  x19, x20
    bge  pcsv_fin
    ldrb w25, [x19], #1         // leer byte y avanzar puntero
    cmp  w25, '\n'
    bne  pcsv_skip_header
    // Aqui x19 apunta al inicio de la primera fila de datos

    // ---- Loop principal: procesar cada fila ----------------
pcsv_fila:
    // Condicion de parada: 30 datos o fin de buffer
    cmp  x21, N_DATOS
    bge  pcsv_fin
    cmp  x19, x20
    bge  pcsv_fin

    // Verificar marcador de fin '$'
    ldrb w25, [x19]
    cmp  w25, '$'
    beq  pcsv_fin

    // Resetear estado para nueva fila
    mov  x22, 0                 // columna = 0
    mov  x23, 0                 // acumulador = 0

    // ---- Loop interno: leer columnas de la fila ------------
pcsv_columna:
    cmp  x19, x20
    bge  pcsv_fin

    ldrb w25, [x19], #1         // leer siguiente byte

    // --- Ignorar retorno de carro \r ---
    cmp  w25, '\r'
    beq  pcsv_columna

    // --- Fin de linea \n ---
    cmp  w25, '\n'
    beq  pcsv_fin_linea

    // --- Separador de columna , ---
    cmp  w25, ','
    beq  pcsv_separador

    // --- Es un digito ASCII ---
    // Verificar que sea '0'..'9'
    cmp  w25, '0'
    blt  pcsv_columna
    cmp  w25, '9'
    bgt  pcsv_columna

    // acum = acum * 10 + (digito - '0')
    mov  x9,  10
    mul  x23, x23, x9
    sub  w25, w25, '0'
    add  x23, x23, x25
    b    pcsv_columna

    // --- Encontramos separador , ---
pcsv_separador:
    // Si esta columna es la que buscamos, guardar y saltar resto
    cmp  x22, COL_OBJETIVO
    beq  pcsv_guardar_valor

    // Si no, pasar a la siguiente columna
    add  x22, x22, 1
    mov  x23, 0                 // resetear acumulador
    b    pcsv_columna

    // --- Fin de linea: si la columna objetivo era la ultima --
pcsv_fin_linea:
    cmp  x22, COL_OBJETIVO
    beq  pcsv_guardar_valor
    // Si no encontramos el valor en esta fila, igual avanzar
    add  x21, x21, 1
    b    pcsv_fila

    // --- Guardar valor en arr_datos[x21] ---
pcsv_guardar_valor:
    str  x23, [x24, x21, lsl #3]    // arr_datos[i] = acum
    add  x21, x21, 1

    // Saltar el resto de la fila hasta \n
pcsv_skip_resto_fila:
    cmp  x19, x20
    bge  pcsv_fin
    ldrb w25, [x19], #1
    cmp  w25, '\n'
    bne  pcsv_skip_resto_fila
    b    pcsv_fila

pcsv_fin:
    // Restaurar registros
    ldp  x25, x26, [sp, #64]
    ldp  x23, x24, [sp, #48]
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #80
    ret


// ===========================================================
// SUBRUTINA: subr_calcular_tendencia
//
// Recorre arr_datos[0..29] comparando cada dato con el anterior.
// Calcula:
//   - INCREMENTS    : cantidad de veces que dato[i] > dato[i-1]
//   - DECREMENTS    : cantidad de veces que dato[i] < dato[i-1]
//   - MAX_UP_STREAK : racha mas larga de incrementos consecutivos
//   - MAX_DOWN_STREAK: racha mas larga de decrementos consecutivos
//   - ACCUM_DIFF    : suma de (dato[i] - dato[i-1]) para i=1..29
//
// Formulas del proyecto:
//   DIF_i    = X_i - X_(i-1)
//   DIF_ACUM = suma de todos los DIF_i
//   DIF_ACUM > 0  -> TREND = UP
//   DIF_ACUM < 0  -> TREND = DOWN
//   DIF_ACUM = 0  -> TREND = STABLE
//
// Registros utilizados:
//   x19 = puntero base de arr_datos
//   x20 = indice i (1 .. 29)
//   x21 = contador de incrementos
//   x22 = contador de decrementos
//   x23 = racha de incrementos actual
//   x24 = racha de decrementos actual
//   x25 = max racha incrementos (MAX_UP_STREAK)
//   x26 = max racha decrementos (MAX_DOWN_STREAK)
//   x27 = diferencia acumulada   (ACCUM_DIFF)
//   x9  = dato[i]
//   x10 = dato[i-1]
//   x11 = diferencia actual DIF_i
// ===========================================================
subr_calcular_tendencia:
    stp  x29, x30, [sp, #-80]!
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    stp  x25, x26, [sp, #64]
    mov  x29, sp

    adr  x19, arr_datos

    // Inicializar todos los contadores en 0
    mov  x20, 1                 // i = 1 (comparamos i con i-1)
    mov  x21, 0                 // incrementos = 0
    mov  x22, 0                 // decrementos = 0
    mov  x23, 0                 // racha_up_actual = 0
    mov  x24, 0                 // racha_down_actual = 0
    mov  x25, 0                 // max_up = 0
    mov  x26, 0                 // max_down = 0
    mov  x27, 0                 // accum_diff = 0

calc_loop:
    // Condicion de parada: i == 30
    cmp  x20, N_DATOS
    bge  calc_fin

    // Cargar dato[i-1] y dato[i]
    sub  x9,  x20, 1
    ldr  x10, [x19, x9,  lsl #3]   // x10 = dato[i-1]
    ldr  x9,  [x19, x20, lsl #3]   // x9  = dato[i]

    // DIF_i = dato[i] - dato[i-1]
    sub  x11, x9, x10

    // ACCUM_DIFF += DIF_i
    add  x27, x27, x11

    // Clasificar DIF_i
    cmp  x11, 0
    bgt  calc_es_incremento
    blt  calc_es_decremento

    // --- DIF_i == 0 : igual, resetear ambas rachas ----------
    mov  x23, 0
    mov  x24, 0
    b    calc_siguiente

    // --- DIF_i > 0 : incremento ----------------------------
calc_es_incremento:
    add  x21, x21, 1            // incrementos++
    add  x23, x23, 1            // racha_up++
    mov  x24, 0                 // resetear racha_down

    // Actualizar MAX_UP_STREAK si racha_up > max_up
    cmp  x23, x25
    ble  calc_siguiente
    mov  x25, x23               // max_up = racha_up
    b    calc_siguiente

    // --- DIF_i < 0 : decremento ----------------------------
calc_es_decremento:
    add  x22, x22, 1            // decrementos++
    add  x24, x24, 1            // racha_down++
    mov  x23, 0                 // resetear racha_up

    // Actualizar MAX_DOWN_STREAK si racha_down > max_down
    cmp  x24, x26
    ble  calc_siguiente
    mov  x26, x24               // max_down = racha_down

calc_siguiente:
    add  x20, x20, 1            // i++
    b    calc_loop

calc_fin:
    // Guardar resultados en memoria BSS
    adr  x9, res_increments
    str  x21, [x9]

    adr  x9, res_decrements
    str  x22, [x9]

    adr  x9, res_max_up
    str  x25, [x9]

    adr  x9, res_max_down
    str  x26, [x9]

    adr  x9, res_accum_diff
    str  x27, [x9]

    ldp  x25, x26, [sp, #64]
    ldp  x23, x24, [sp, #48]
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #80
    ret


// ===========================================================
// SUBRUTINA: subr_escribir_resultado
//
// Crea resultado_tendencia.txt y escribe todas las lineas
// con el formato exacto requerido por el proyecto.
//
// Registros utilizados:
//   x19 = fd del archivo de salida
// ===========================================================
subr_escribir_resultado:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x29, sp

    // Crear/abrir archivo de salida
    mov  x8,  SYS_OPENAT
    mov  x0,  AT_FDCWD
    adr  x1,  archivo_salida
    mov  x2,  O_WRONLY | O_CREAT | O_TRUNC
    mov  x3,  PERM_644
    svc  0
    cmp  x0,  0
    blt  er_fin
    mov  x19, x0                // x19 = fd de salida

    // --- Linea 1: MODULE=ADVANCED_TREND --------------------
    adr  x0, str_module
    mov  x1, str_module_len
    bl   subr_escribir_buf

    // --- Linea 2: TOTAL_VALUES=30 --------------------------
    adr  x0, str_total
    mov  x1, str_total_len
    bl   subr_escribir_buf

    // --- Linea 3: INCREMENTS=<valor> -----------------------
    adr  x0, str_inc_label
    mov  x1, str_inc_label_len
    bl   subr_escribir_buf
    adr  x9, res_increments
    ldr  x0, [x9]
    bl   subr_escribir_entero_nl

    // --- Linea 4: DECREMENTS=<valor> -----------------------
    adr  x0, str_dec_label
    mov  x1, str_dec_label_len
    bl   subr_escribir_buf
    adr  x9, res_decrements
    ldr  x0, [x9]
    bl   subr_escribir_entero_nl

    // --- Linea 5: MAX_UP_STREAK=<valor> --------------------
    adr  x0, str_mup_label
    mov  x1, str_mup_label_len
    bl   subr_escribir_buf
    adr  x9, res_max_up
    ldr  x0, [x9]
    bl   subr_escribir_entero_nl

    // --- Linea 6: MAX_DOWN_STREAK=<valor> ------------------
    adr  x0, str_mdn_label
    mov  x1, str_mdn_label_len
    bl   subr_escribir_buf
    adr  x9, res_max_down
    ldr  x0, [x9]
    bl   subr_escribir_entero_nl

    // --- Linea 7: ACCUM_DIFF=<valor> (puede ser negativo) --
    adr  x0, str_acc_label
    mov  x1, str_acc_label_len
    bl   subr_escribir_buf
    adr  x9, res_accum_diff
    ldr  x0, [x9]
    bl   subr_escribir_entero_con_signo_nl

    // --- Linea 8: TREND=UP / DOWN / STABLE -----------------
    adr  x9, res_accum_diff
    ldr  x0, [x9]
    cmp  x0, 0
    bgt  er_trend_up
    blt  er_trend_down

    // STABLE
    adr  x0, str_trend_stable
    mov  x1, str_trend_stable_len
    bl   subr_escribir_buf
    b    er_cerrar

er_trend_up:
    adr  x0, str_trend_up
    mov  x1, str_trend_up_len
    bl   subr_escribir_buf
    b    er_cerrar

er_trend_down:
    adr  x0, str_trend_down
    mov  x1, str_trend_down_len
    bl   subr_escribir_buf

er_cerrar:
    mov  x8, SYS_CLOSE
    mov  x0, x19
    svc  0

er_fin:
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret


// ===========================================================
// SUBRUTINA: subr_escribir_buf
// Escribe x1 bytes desde la direccion x0 al fd x19.
// ===========================================================
subr_escribir_buf:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    mov  x8,  SYS_WRITE
    mov  x2,  x1                // longitud
    mov  x1,  x0                // buffer
    mov  x0,  x19               // fd
    svc  0

    ldp  x29, x30, [sp], #16
    ret


// ===========================================================
// SUBRUTINA: subr_escribir_entero_nl
//
// Convierte el entero en x0 (sin signo) a ASCII y lo escribe
// al archivo seguido de '\n'.
//
// Algoritmo: division sucesiva por 10, los digitos salen
// en orden inverso, los ponemos al final del buffer y
// escribimos desde el primero hacia atras.
//
// Registros:
//   x0  = valor a convertir (entrada)
//   x9  = base del buffer buf_conv
//   x10 = cursor (avanza hacia atras desde el final)
//   x11 = cociente temporal
//   x12 = resto (digito actual)
// ===========================================================
subr_escribir_entero_nl:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    adr  x9,  buf_conv
    add  x10, x9, #28           // cursor empieza al final

    // Escribir '\n' en la ultima posicion
    mov  w12, '\n'
    strb w12, [x10]

    // Caso especial: valor == 0
    cbnz x0, sein_loop
    mov  w12, '0'
    sub  x10, x10, #1
    strb w12, [x10]
    b    sein_escribir

sein_loop:
    cbz  x0, sein_escribir

    mov  x11, 10
    udiv x12, x0, x11           // cociente = valor / 10
    msub x12, x12, x11, x0     // resto    = valor - cociente*10
    add  w12, w12, '0'          // convertir a ASCII
    sub  x10, x10, #1
    strb w12, [x10]             // guardar digito
    udiv x0,  x0, x11           // valor = cociente
    b    sein_loop

sein_escribir:
    // Calcular longitud: desde x10 hasta x9+28 inclusive + \n
    adr  x9, buf_conv
    add  x9, x9, #28
    sub  x1, x9, x10
    add  x1, x1, #1             // +1 por el \n
    mov  x0, x10
    bl   subr_escribir_buf

    ldp  x29, x30, [sp], #16
    ret


// ===========================================================
// SUBRUTINA: subr_escribir_entero_con_signo_nl
//
// Igual que subr_escribir_entero_nl pero si x0 es negativo
// escribe el signo '-' antes de los digitos.
// ===========================================================
subr_escribir_entero_con_signo_nl:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x29, sp

    // ¿Es negativo?
    cmp  x0, 0
    bge  secsn_positivo

    // Guardar valor absoluto
    neg  x20, x0                // x20 = abs(valor)

    // Escribir el signo '-'
    mov  x8,  SYS_WRITE
    mov  x0,  x19
    adr  x1,  str_minus
    mov  x2,  1
    svc  0

    // Escribir el valor absoluto + \n
    mov  x0,  x20
    bl   subr_escribir_entero_nl
    b    secsn_fin

secsn_positivo:
    // Solo escribir el valor + \n
    bl   subr_escribir_entero_nl

secsn_fin:
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// ---- Fin del archivo --------------------------------------
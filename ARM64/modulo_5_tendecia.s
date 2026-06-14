// ============================================================
// modulo_5_tendecia.s
// Integrante 5 - Tendencia Acumulada Avanzada
// Curso: ACYE1 - Vacaciones Junio 2026
//
// Lee la columna que el usuario seleccione desde el dashboard.
// El numero de columna llega como argv[1] cuando Python ejecuta
// el binario. Si no viene argumento, usa columna 2 (TEMP).
//
// Formulas:
//   DIF_i    = X_i - X_(i-1)
//   DIF_ACUM = suma(DIF_i)
//   DIF_ACUM > 0 => TREND=UP
//   DIF_ACUM < 0 => TREND=DOWN
//   DIF_ACUM = 0 => TREND=STABLE
//
// Archivo de entrada:  lecturas.csv
// Archivo de salida:   resultado_tendencia.txt
// ============================================================

.extern leer_datos
.extern int_a_ascii
.extern ascii_a_int
.extern datos

.equ SYS_OPENAT,  56
.equ SYS_CLOSE,   57
.equ SYS_WRITE,   64
.equ SYS_EXIT,    93
.equ AT_FDCWD,   -100
.equ O_WRONLY,    1
.equ O_CREAT,     64
.equ O_TRUNC,     512
.equ PERM_644,    0644
.equ N_DATOS,     30

.section .data

archivo_salida:   .asciz "resultado_tendencia.txt"

str_module:       .ascii "MODULE=ADVANCED_TREND\n"
.equ str_module_len, . - str_module
str_total:        .ascii "TOTAL_VALUES=30\n"
.equ str_total_len, . - str_total
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
str_minus:        .ascii "-"

.section .bss

buf_conv:         .skip 32

// los 5 resultados del calculo de tendencia
res_increments:   .skip 8
res_decrements:   .skip 8
res_max_up:       .skip 8
res_max_down:     .skip 8
res_accum_diff:   .skip 8

.section .text
.global _start

_start:
    // --------------------------------------------------------
    // LECTURA DE argv[1]: el numero de columna que manda Python
    // [sp]    = argc
    // [sp+16] = puntero al string de argv[1] (ej: "4" para HUM_SUELO_1)
    // Si no viene argumento usamos columna 2 (TEMP) por defecto
    // --------------------------------------------------------
    ldr x0, [sp]            // x0 = argc
    cmp x0, #2              // hay al menos 1 argumento?
    blt .usar_default_5     // no -> default

    ldr x0, [sp, #16]       // x0 = puntero a argv[1]
    bl  ascii_a_int          // convierte string a entero en x0
    b   .llamar_leer_5

.usar_default_5:
    mov x0, #2              // default: columna 2 = TEMP

.llamar_leer_5:
    // leer_datos llena datos[] con los 30 valores de la columna x0
    bl   leer_datos

    // --------------------------------------------------------
    // CALCULAR TENDENCIA: comparar cada dato con el anterior
    // Guardamos los resultados en res_increments ... res_accum_diff
    // --------------------------------------------------------
    adr  x0,  datos
    adr  x1,  res_increments
    bl   calcular_tendencia

    // escribir al archivo
    bl   escribir_resultado

    // mostrar tambien en terminal
    mov  x19, #1            // x19 = fd stdout
    bl   escribir_contenido

    mov  x8,  SYS_EXIT
    mov  x0,  #0
    svc  0


// ============================================================
// calcular_tendencia
// Recorre los 30 datos comparando cada uno con el anterior
//
// Entrada:
//   x0 = puntero al arreglo de datos
//   x1 = puntero donde guardar los 5 resultados
//
// Registros internos:
//   x19 = arreglo de datos
//   x20 = donde guardamos resultados
//   x21 = indice i (empieza en 1 para poder ver datos[i-1])
//   x22 = contador de incrementos
//   x23 = contador de decrementos
//   x24 = racha de subida actual
//   x25 = racha de bajada actual
//   x26 = racha maxima de subida
//   x27 = racha maxima de bajada
//   x28 = diferencia acumulada (puede ser negativa)
// ============================================================
calcular_tendencia:
    stp  x29, x30, [sp, #-96]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    stp  x25, x26, [sp, #64]
    stp  x27, x28, [sp, #80]

    mov  x19, x0            // puntero a datos
    mov  x20, x1            // puntero a resultados
    mov  x21, #1            // arrancamos en i=1 para comparar con datos[i-1]
    mov  x22, #0
    mov  x23, #0
    mov  x24, #0
    mov  x25, #0
    mov  x26, #0
    mov  x27, #0
    mov  x28, #0

ct_loop:
    cmp  x21, N_DATOS
    bge  ct_fin

    // DIF_i = datos[i] - datos[i-1]
    sub  x9,  x21, #1
    ldr  x10, [x19, x9,  lsl #3]   // datos[i-1]
    ldr  x9,  [x19, x21, lsl #3]   // datos[i]
    sub  x11, x9,  x10             // diferencia

    add  x28, x28, x11             // acumular diferencia

    cmp  x11, #0
    bgt  ct_incremento
    blt  ct_decremento

    // diferencia = 0: resetear ambas rachas
    mov  x24, #0
    mov  x25, #0
    b    ct_siguiente

ct_incremento:
    add  x22, x22, #1              // un incremento mas
    add  x24, x24, #1              // racha de subida crece
    mov  x25, #0                   // racha de bajada se resetea
    cmp  x24, x26
    ble  ct_siguiente
    mov  x26, x24                  // actualizar record de racha subida
    b    ct_siguiente

ct_decremento:
    add  x23, x23, #1              // un decremento mas
    add  x25, x25, #1              // racha de bajada crece
    mov  x24, #0                   // racha de subida se resetea
    cmp  x25, x27
    ble  ct_siguiente
    mov  x27, x25                  // actualizar record de racha bajada

ct_siguiente:
    add  x21, x21, #1
    b    ct_loop

ct_fin:
    // guardar los 5 resultados en orden
    str  x22, [x20, #0]            // INCREMENTS
    str  x23, [x20, #8]            // DECREMENTS
    str  x26, [x20, #16]           // MAX_UP_STREAK
    str  x27, [x20, #24]           // MAX_DOWN_STREAK
    str  x28, [x20, #32]           // ACCUM_DIFF (puede ser negativo)

    ldp  x27, x28, [sp, #80]
    ldp  x25, x26, [sp, #64]
    ldp  x23, x24, [sp, #48]
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #96
    ret


// ============================================================
// escribir_resultado
// Abre el archivo de salida y llama a escribir_contenido
// ============================================================
escribir_resultado:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x29, sp

    mov  x8,  SYS_OPENAT
    mov  x0,  AT_FDCWD
    adr  x1,  archivo_salida
    mov  x2,  O_WRONLY | O_CREAT | O_TRUNC
    mov  x3,  PERM_644
    svc  0
    cmp  x0,  #0
    blt  er_fin
    mov  x19, x0            // x19 = descriptor del archivo

    bl   escribir_contenido

    mov  x8,  SYS_CLOSE
    mov  x0,  x19
    svc  0

er_fin:
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret


// ============================================================
// escribir_contenido
// Escribe todo al fd en x19 (puede ser archivo o stdout=1)
// ============================================================
escribir_contenido:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x29, sp

    adr  x0,  str_module
    mov  x1,  str_module_len
    bl   escribir_buf

    adr  x0,  str_total
    mov  x1,  str_total_len
    bl   escribir_buf

    // INCREMENTS=valor
    adr  x0,  str_inc_lbl
    mov  x1,  str_inc_lbl_len
    bl   escribir_buf
    adr  x0,  res_increments
    ldr  x0,  [x0]
    bl   escribir_uint_nl

    // DECREMENTS=valor
    adr  x0,  str_dec_lbl
    mov  x1,  str_dec_lbl_len
    bl   escribir_buf
    adr  x0,  res_decrements
    ldr  x0,  [x0]
    bl   escribir_uint_nl

    // MAX_UP_STREAK=valor
    adr  x0,  str_mup_lbl
    mov  x1,  str_mup_lbl_len
    bl   escribir_buf
    adr  x0,  res_max_up
    ldr  x0,  [x0]
    bl   escribir_uint_nl

    // MAX_DOWN_STREAK=valor
    adr  x0,  str_mdn_lbl
    mov  x1,  str_mdn_lbl_len
    bl   escribir_buf
    adr  x0,  res_max_down
    ldr  x0,  [x0]
    bl   escribir_uint_nl

    // ACCUM_DIFF=valor (puede ser negativo, usamos escribir_int_nl)
    adr  x0,  str_acc_lbl
    mov  x1,  str_acc_lbl_len
    bl   escribir_buf
    adr  x0,  res_accum_diff
    ldr  x0,  [x0]
    bl   escribir_int_nl

    // TREND=UP/DOWN/STABLE segun signo de ACCUM_DIFF
    adr  x0,  res_accum_diff
    ldr  x0,  [x0]
    cmp  x0,  #0
    bgt  ec_up
    blt  ec_down

    // ACCUM_DIFF = 0 -> STABLE
    adr  x0,  str_trend_stable
    mov  x1,  str_trend_stable_len
    bl   escribir_buf
    b    ec_fin

ec_up:
    adr  x0,  str_trend_up
    mov  x1,  str_trend_up_len
    bl   escribir_buf
    b    ec_fin

ec_down:
    adr  x0,  str_trend_down
    mov  x1,  str_trend_down_len
    bl   escribir_buf

ec_fin:
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret


// escribe x1 bytes desde x0 al fd en x19
escribir_buf:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    mov  x8,  SYS_WRITE
    mov  x2,  x1
    mov  x1,  x0
    mov  x0,  x19
    svc  0
    ldp  x29, x30, [sp], #16
    ret


// convierte x0 (positivo) a texto y escribe al fd con \n al final
escribir_uint_nl:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    adr  x1,  buf_conv
    bl   int_a_ascii        // convierte x0 al texto en buf_conv
    adr  x0,  buf_conv
    mov  x1,  #0
eun_len:
    ldrb w2,  [x0, x1]
    cbz  w2,  eun_escribir
    add  x1,  x1,  #1
    b    eun_len
eun_escribir:
    mov  w2,  #10           // agregar \n al final
    strb w2,  [x0, x1]
    add  x1,  x1,  #1
    bl   escribir_buf
    ldp  x29, x30, [sp], #16
    ret


// igual que escribir_uint_nl pero maneja numeros negativos
// si x0 < 0: escribe '-' primero y luego el valor absoluto
escribir_int_nl:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x29, sp

    cmp  x0,  #0
    bge  ein_positivo

    // es negativo: escribir el signo menos primero
    mov  x20, x0
    neg  x20, x20           // valor absoluto en x20
    mov  x8,  SYS_WRITE
    mov  x0,  x19
    adr  x1,  str_minus
    mov  x2,  #1
    svc  0
    mov  x0,  x20           // pasar el valor absoluto a escribir_uint_nl

ein_positivo:
    bl   escribir_uint_nl

    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

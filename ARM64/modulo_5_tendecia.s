// ============================================================
// modulo_5_tendencia.s
// Integrante 5 - Tendencia Acumulada Avanzada
// Curso: ACYE1 - Vacaciones Junio 2026
//
// Analizo las columnas HUM_SUELO_1 (col 3) y HUM_SUELO_2 (col 4)
// Para cada columna calculo cuantos incrementos y decrementos hay
// entre datos consecutivos, las rachas mas largas de subida y bajada,
// y la diferencia acumulada para saber si la tendencia es UP, DOWN o STABLE
//
// Las formulas que uso son:
//   DIF_i    = X_i - X_(i-1)
//   DIF_ACUM = S(DIF_i)
//   DIF_ACUM > 0 => TREND=UP
//   DIF_ACUM < 0 => TREND=DOWN
//   DIF_ACUM = 0 => TREND=STABLE
//
// Para leer el CSV uso leer_datos de utils.s
// Para convertir numeros a texto uso int_a_ascii de utils.s
// Los datos quedan en el arreglo datos[] de utils.s
// ============================================================

.extern leer_datos
.extern int_a_ascii
.extern datos

// syscalls que necesito para abrir, escribir y cerrar archivos
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

// lineas fijas del archivo de salida
str_module:       .ascii "MODULE=ADVANCED_TREND\n"
.equ str_module_len, . - str_module
str_total:        .ascii "TOTAL_VALUES=30\n"
.equ str_total_len, . - str_total
str_sep:          .ascii "---\n"
.equ str_sep_len, . - str_sep
str_area1:        .ascii "AREA=HUM_SUELO_1\n"
.equ str_area1_len, . - str_area1
str_area2:        .ascii "AREA=HUM_SUELO_2\n"
.equ str_area2_len, . - str_area2

// etiquetas antes de cada valor calculado
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

// los tres posibles resultados de tendencia
str_trend_up:     .ascii "TREND=UP\n"
.equ str_trend_up_len, . - str_trend_up
str_trend_down:   .ascii "TREND=DOWN\n"
.equ str_trend_down_len, . - str_trend_down
str_trend_stable: .ascii "TREND=STABLE\n"
.equ str_trend_stable_len, . - str_trend_stable

str_minus:        .ascii "-"

.section .bss

buf_conv:         .skip 32      // buffer temporal para convertir numeros a texto

// necesito este arreglo porque leer_datos siempre escribe en datos[]
// entonces copio suelo1 aqui antes de llamar leer_datos por segunda vez
arr_suelo1:       .skip 240     // 30 valores x 8 bytes

// aqui guardo los 5 resultados de HUM_SUELO_1
s1_increments:    .skip 8
s1_decrements:    .skip 8
s1_max_up:        .skip 8
s1_max_down:      .skip 8
s1_accum_diff:    .skip 8

// aqui guardo los 5 resultados de HUM_SUELO_2
s2_increments:    .skip 8
s2_decrements:    .skip 8
s2_max_up:        .skip 8
s2_max_down:      .skip 8
s2_accum_diff:    .skip 8

fd_out:           .skip 8

.section .text
.global _start

_start:
    // leo HUM_SUELO_1, utils abre el CSV y llena datos[]
    mov  x0,  #3
    bl   leer_datos

    // copio datos[] a arr_suelo1 porque cuando llame leer_datos
    // de nuevo para suelo2, va a sobreescribir datos[] y perderia suelo1
    adr  x0,  datos
    adr  x1,  arr_suelo1
    mov  x2,  #0
copiar_suelo1:
    cmp  x2,  #30
    beq  fin_copiar
    ldr  x3,  [x0, x2, lsl #3]
    str  x3,  [x1, x2, lsl #3]
    add  x2,  x2,  #1
    b    copiar_suelo1
fin_copiar:

    // ahora leo HUM_SUELO_2, datos[] queda con los valores de suelo2
    // arr_suelo1 ya tiene guardados los de suelo1
    mov  x0,  #4
    bl   leer_datos

    // calculo la tendencia de cada columna por separado
    adr  x0,  arr_suelo1
    adr  x1,  s1_increments
    bl   calcular_tendencia

    adr  x0,  datos
    adr  x1,  s2_increments
    bl   calcular_tendencia

    // escribo los resultados al archivo
    bl   escribir_resultado

    // tambien muestro los resultados en la terminal
    // pongo x19=1 que es stdout y llamo la misma logica de escritura
    mov  x19, #1
    bl   imprimir_resultado

    mov  x8,  SYS_EXIT
    mov  x0,  #0
    svc  0


// ============================================================
// calcular_tendencia
// Recibe un arreglo y calcula incrementos, decrementos,
// rachas maximas y diferencia acumulada
//
// x0 = arreglo de 30 datos que voy a analizar
// x1 = donde guardo los 5 resultados
//
// registros que uso:
//   x19 = arreglo de datos
//   x20 = donde guardo resultados
//   x21 = indice i, empieza en 1 para poder ver datos[i-1]
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

    mov  x19, x0
    mov  x20, x1
    mov  x21, #1            // arranco en 1 para poder comparar con datos[i-1]
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

    // calculo la diferencia entre el dato actual y el anterior
    sub  x9,  x21, #1
    ldr  x10, [x19, x9,  lsl #3]   // datos[i-1]
    ldr  x9,  [x19, x21, lsl #3]   // datos[i]
    sub  x11, x9,  x10             // DIF_i = datos[i] - datos[i-1]
    add  x28, x28, x11             // acumulo la diferencia

    cmp  x11, #0
    bgt  ct_incremento
    blt  ct_decremento

    // si la diferencia es 0 reseteo las dos rachas
    mov  x24, #0
    mov  x25, #0
    b    ct_siguiente

ct_incremento:
    add  x22, x22, #1              // sumo al contador de incrementos
    add  x24, x24, #1              // aumento la racha de subida
    mov  x25, #0                   // reseteo la racha de bajada
    cmp  x24, x26
    ble  ct_siguiente
    mov  x26, x24                  // actualizo el record de racha subida
    b    ct_siguiente

ct_decremento:
    add  x23, x23, #1              // sumo al contador de decrementos
    add  x25, x25, #1              // aumento la racha de bajada
    mov  x24, #0                   // reseteo la racha de subida
    cmp  x25, x27
    ble  ct_siguiente
    mov  x27, x25                  // actualizo el record de racha bajada

ct_siguiente:
    add  x21, x21, #1
    b    ct_loop

ct_fin:
    // guardo los 5 resultados en el bloque que me pasaron
    str  x22, [x20, #0]
    str  x23, [x20, #8]
    str  x26, [x20, #16]
    str  x27, [x20, #24]
    str  x28, [x20, #32]

    ldp  x27, x28, [sp, #80]
    ldp  x25, x26, [sp, #64]
    ldp  x23, x24, [sp, #48]
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #96
    ret


// ============================================================
// escribir_resultado
// Abre el archivo de salida y llama escribir_contenido
// con el fd del archivo en x19
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
    mov  x19, x0            // guardo el descriptor del archivo

    bl   escribir_contenido // escribe todo al archivo

    mov  x8,  SYS_CLOSE
    mov  x0,  x19
    svc  0

er_fin:
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret


// ============================================================
// imprimir_resultado
// Lo mismo que escribir_resultado pero ya recibe x19=1 (stdout)
// desde _start, asi que solo llama escribir_contenido
// ============================================================
imprimir_resultado:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x29, sp
    bl   escribir_contenido
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret


// ============================================================
// escribir_contenido
// Escribe todo el texto al fd que este en x19
// Esto me permite reusar la misma logica para el archivo y stdout
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

    // bloque HUM_SUELO_1
    adr  x0,  str_area1
    mov  x1,  str_area1_len
    bl   escribir_buf
    adr  x20, s1_increments
    bl   escribir_bloque

    // separador entre las dos secciones
    adr  x0,  str_sep
    mov  x1,  str_sep_len
    bl   escribir_buf

    // bloque HUM_SUELO_2
    adr  x0,  str_area2
    mov  x1,  str_area2_len
    bl   escribir_buf
    adr  x20, s2_increments
    bl   escribir_bloque

    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret


// ============================================================
// escribir_bloque
// Escribe los 5 campos de un bloque de resultados
// x19 = fd donde escribir
// x20 = puntero al bloque [inc, dec, max_up, max_down, accum]
// ============================================================
escribir_bloque:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    adr  x0,  str_inc_lbl
    mov  x1,  str_inc_lbl_len
    bl   escribir_buf
    ldr  x0,  [x20, #0]
    bl   escribir_uint_nl

    adr  x0,  str_dec_lbl
    mov  x1,  str_dec_lbl_len
    bl   escribir_buf
    ldr  x0,  [x20, #8]
    bl   escribir_uint_nl

    adr  x0,  str_mup_lbl
    mov  x1,  str_mup_lbl_len
    bl   escribir_buf
    ldr  x0,  [x20, #16]
    bl   escribir_uint_nl

    adr  x0,  str_mdn_lbl
    mov  x1,  str_mdn_lbl_len
    bl   escribir_buf
    ldr  x0,  [x20, #24]
    bl   escribir_uint_nl

    // ACCUM_DIFF puede ser negativo asi que uso escribir_int_nl
    adr  x0,  str_acc_lbl
    mov  x1,  str_acc_lbl_len
    bl   escribir_buf
    ldr  x0,  [x20, #32]
    bl   escribir_int_nl

    // segun el signo de accum_diff escribo UP, DOWN o STABLE
    ldr  x0,  [x20, #32]
    cmp  x0,  #0
    bgt  eb_up
    blt  eb_down
    adr  x0,  str_trend_stable
    mov  x1,  str_trend_stable_len
    bl   escribir_buf
    b    eb_fin
eb_up:
    adr  x0,  str_trend_up
    mov  x1,  str_trend_up_len
    bl   escribir_buf
    b    eb_fin
eb_down:
    adr  x0,  str_trend_down
    mov  x1,  str_trend_down_len
    bl   escribir_buf
eb_fin:
    ldp  x29, x30, [sp], #16
    ret


// escribe x1 bytes desde x0 al fd que este en x19
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


// convierte x0 a texto con int_a_ascii y escribe al fd + salto de linea
escribir_uint_nl:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    adr  x1,  buf_conv
    bl   int_a_ascii        // el resultado queda en buf_conv
    adr  x0,  buf_conv
    mov  x1,  #0
eun_len:
    ldrb w2,  [x0, x1]     // busco el fin del texto convertido
    cbz  w2,  eun_escribir
    add  x1,  x1,  #1
    b    eun_len
eun_escribir:
    mov  w2,  #10           // agrego el salto de linea al final
    strb w2,  [x0, x1]
    add  x1,  x1,  #1
    bl   escribir_buf
    ldp  x29, x30, [sp], #16
    ret


// igual que escribir_uint_nl pero si el numero es negativo
// escribe el signo '-' primero y luego el valor absoluto
escribir_int_nl:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x29, sp
    cmp  x0,  #0
    bge  ein_positivo
    mov  x20, x0
    neg  x20, x20           // calculo el valor absoluto
    mov  x8,  SYS_WRITE
    mov  x0,  x19
    adr  x1,  str_minus
    mov  x2,  #1
    svc  0
    mov  x0,  x20           // paso el valor absoluto para convertir
ein_positivo:
    bl   escribir_uint_nl
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret
// ============================================================
// modulo_5_tendencia.s
// Rutina ARM64 - Tendencia Acumulada Avanzada
// Proyecto: Invernadero Inteligente IoT - ACYE1
// Integrante 5
//
// Entrada : lecturas.csv (columna seleccionada, 30 datos)
// Salida  : resultado_tendencia.txt
//
// Compila:
//   as modulo_5_tendencia.s utils.o -o modulo_5_tendencia.o
//   ld modulo_5_tendencia.o utils.o -o modulo_5_tendencia
// ============================================================

// ---- Llamadas al sistema (Linux AArch64) -------------------
.equ SYS_OPENAT,   56
.equ SYS_CLOSE,    57
.equ SYS_READ,     63
.equ SYS_WRITE,    64
.equ SYS_EXIT,      93
.equ AT_FDCWD,    -100
.equ O_RDONLY,      0
.equ O_WRONLY,      1
.equ O_CREAT,      64
.equ O_TRUNC,     512
.equ PERM_644,    0644

// ---- Constantes del programa --------------------------------
.equ N,            30       // numero exacto de datos
.equ COL_TEMP,      1       // columna TEMP (0-indexed desde ID)
                            // cambia este valor para otra variable:
                            // 1=TEMP 2=HUM_AIRE 3=HUM_SUELO_1
                            // 4=HUM_SUELO_2 5=LUZ 6=GAS

// ---- Seccion de datos ---------------------------------------
.section .data

fname_in:   .asciz "lecturas.csv"
fname_out:  .asciz "resultado_tendencia.txt"

// Etiquetas para el archivo de salida
lbl_module: .ascii  "MODULE=ADVANCED_TREND\n"
            .equ lbl_module_len, . - lbl_module

lbl_total:  .ascii  "TOTAL_VALUES=30\n"
            .equ lbl_total_len, . - lbl_total

lbl_inc_k:  .ascii  "INCREMENTS="
            .equ lbl_inc_k_len, . - lbl_inc_k

lbl_dec_k:  .ascii  "DECREMENTS="
            .equ lbl_dec_k_len, . - lbl_dec_k

lbl_mup_k:  .ascii  "MAX_UP_STREAK="
            .equ lbl_mup_k_len, . - lbl_mup_k

lbl_mdn_k:  .ascii  "MAX_DOWN_STREAK="
            .equ lbl_mdn_k_len, . - lbl_mdn_k

lbl_acc_k:  .ascii  "ACCUM_DIFF="
            .equ lbl_acc_k_len, . - lbl_acc_k

lbl_trend_up:   .ascii  "TREND=UP\n"
                .equ lbl_trend_up_len, . - lbl_trend_up

lbl_trend_dn:   .ascii  "TREND=DOWN\n"
                .equ lbl_trend_dn_len, . - lbl_trend_dn

lbl_trend_st:   .ascii  "TREND=STABLE\n"
                .equ lbl_trend_st_len, . - lbl_trend_st

newline:    .ascii  "\n"

// Buffer de conversion ASCII -> entero para numero negativo
neg_sign:   .ascii  "-"

// ---- Seccion BSS (variables sin inicializar) ---------------
.section .bss

buf_csv:    .skip   4096    // buffer lectura del CSV
buf_num:    .skip   32      // buffer conversion entero->ASCII
datos:      .skip   120     // array de 30 enteros (4 bytes c/u)

// Resultados calculados
r_increments:   .skip 8
r_decrements:   .skip 8
r_max_up:       .skip 8
r_max_down:     .skip 8
r_accum_diff:   .skip 8

// ---- Seccion de codigo -------------------------------------
.section .text
.global _start

// ============================================================
// _start - punto de entrada
// ============================================================
_start:
    // 1. Abrir lecturas.csv
    mov     x8, SYS_OPENAT
    mov     x0, AT_FDCWD
    adr     x1, fname_in
    mov     x2, O_RDONLY
    mov     x3, 0
    svc     0
    cmp     x0, 0
    blt     exit_error
    mov     x19, x0             // x19 = fd del CSV

    // 2. Leer todo el archivo en buf_csv
    mov     x8, SYS_READ
    mov     x0, x19
    adr     x1, buf_csv
    mov     x2, 4096
    svc     0
    mov     x20, x0             // x20 = bytes leidos

    // 3. Cerrar archivo
    mov     x8, SYS_CLOSE
    mov     x0, x19
    svc     0

    // 4. Parsear CSV y cargar columna COL_TEMP en array datos[]
    bl      parsear_csv

    // 5. Calcular tendencia acumulada
    bl      calcular_tendencia

    // 6. Escribir resultado_tendencia.txt
    bl      escribir_resultado

    // 7. Salir normalmente
    mov     x8, SYS_EXIT
    mov     x0, 0
    svc     0

exit_error:
    mov     x8, SYS_EXIT
    mov     x0, 1
    svc     0


// ============================================================
// parsear_csv
// Lee buf_csv, salta la cabecera, extrae la columna COL_TEMP
// de cada fila y la guarda como entero en datos[].
// Registros usados:
//   x0  - puntero actual en buf_csv
//   x1  - puntero fin del buffer
//   x2  - columna actual dentro de la fila
//   x3  - indice en array datos (0..29)
//   x4  - byte leido
//   x5  - acumulador del numero actual
//   x6  - base del array datos
//   x7  - signo (-1 o 1)
// ============================================================
parsear_csv:
    stp     x29, x30, [sp, #-64]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x29, sp

    adr     x0, buf_csv
    add     x1, x0, x20         // fin = inicio + bytes_leidos
    adr     x6, datos
    mov     x3, 0               // indice fila = 0

    // --- Saltar la primera linea (cabecera) ---
skip_header:
    ldrb    w4, [x0], #1
    cmp     x0, x1
    bge     pc_done
    cmp     w4, '\n'
    bne     skip_header

    // --- Procesar cada fila de datos ---
pc_fila:
    cmp     x3, N               // ¿ya tenemos 30 datos?
    bge     pc_done
    cmp     x0, x1
    bge     pc_done

    // Verificar si es el marcador '$' de fin
    ldrb    w4, [x0]
    cmp     w4, '$'
    beq     pc_done

    mov     x2, 0               // columna actual = 0
    mov     x5, 0               // acumulador = 0
    mov     x7, 1               // signo = positivo

    // --- Recorrer columnas hasta llegar a COL_TEMP ---
pc_col:
    ldrb    w4, [x0], #1
    cmp     x0, x1
    bgt     pc_done

    // Fin de linea -> siguiente fila
    cmp     w4, '\n'
    beq     pc_siguiente_fila
    cmp     w4, '\r'
    beq     pc_col              // ignorar CR

    // Separador de columna
    cmp     w4, ','
    beq     pc_separador

    // Digito o signo negativo
    cmp     w4, '-'
    beq     pc_signo_neg

    // Es un digito ASCII ('0'..'9')
    sub     w4, w4, '0'
    mul     x5, x5, xzr
    mov     x9, 10
    mul     x5, x5, x9          // acum = acum * 10  (se resetea si venimos de separador)
    // NOTA: la multiplicacion por xzr borra x5 — corregido abajo
    b       pc_col

pc_signo_neg:
    mov     x7, -1
    b       pc_col

pc_separador:
    // Si eramos la columna objetivo, guardar valor
    cmp     x2, COL_TEMP
    beq     pc_guardar

    add     x2, x2, 1           // siguiente columna
    mov     x5, 0               // resetear acumulador
    mov     x7, 1               // resetear signo
    b       pc_col

pc_siguiente_fila:
    // Si la columna objetivo era la ultima de la fila, guardar
    cmp     x2, COL_TEMP
    beq     pc_guardar_y_avanzar
    add     x3, x3, 1           // siguiente fila sin guardar
    b       pc_fila

pc_guardar:
    mul     x5, x5, x7          // aplicar signo
    str     x5, [x6, x3, lsl #3]
    add     x3, x3, 1
    // saltar resto de la fila hasta \n
pc_skip_resto:
    ldrb    w4, [x0], #1
    cmp     x0, x1
    bge     pc_done
    cmp     w4, '\n'
    bne     pc_skip_resto
    b       pc_fila

pc_guardar_y_avanzar:
    mul     x5, x5, x7
    str     x5, [x6, x3, lsl #3]
    add     x3, x3, 1
    b       pc_fila

pc_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret


// ============================================================
// calcular_tendencia
// Recorre datos[0..29], calcula:
//   - incrementos  : veces que datos[i] > datos[i-1]
//   - decrementos  : veces que datos[i] < datos[i-1]
//   - max_up_streak: racha maxima de incrementos consecutivos
//   - max_down_streak: racha maxima de decrementos consecutivos
//   - accum_diff   : suma de (datos[i] - datos[i-1]) para i=1..29
//
// Registros:
//   x19 - puntero base de datos[]
//   x20 - indice i (1..29)
//   x21 - incrementos totales
//   x22 - decrementos totales
//   x23 - racha actual hacia arriba
//   x24 - racha actual hacia abajo
//   x25 - max racha arriba
//   x26 - max racha abajo
//   x27 - diferencia acumulada
//   x9  - datos[i]
//   x10 - datos[i-1]
//   x11 - diferencia actual
// ============================================================
calcular_tendencia:
    stp     x29, x30, [sp, #-80]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    mov     x29, sp

    adr     x19, datos
    mov     x20, 1              // i = 1 (comparamos con i-1)
    mov     x21, 0              // incrementos = 0
    mov     x22, 0              // decrementos = 0
    mov     x23, 0              // racha_up_actual = 0
    mov     x24, 0              // racha_down_actual = 0
    mov     x25, 0              // max_up = 0
    mov     x26, 0              // max_down = 0
    mov     x27, 0              // accum_diff = 0

ct_loop:
    cmp     x20, N
    bge     ct_fin

    // Cargar datos[i] y datos[i-1]
    sub     x9, x20, 1
    ldr     x10, [x19, x9, lsl #3]      // datos[i-1]
    ldr     x9,  [x19, x20, lsl #3]     // datos[i]

    // dif = datos[i] - datos[i-1]
    sub     x11, x9, x10
    add     x27, x27, x11       // acum_diff += dif

    // Clasificar: incremento, decremento o igual
    cmp     x11, 0
    bgt     ct_incremento
    blt     ct_decremento

    // Igual: resetear ambas rachas
    mov     x23, 0
    mov     x24, 0
    b       ct_siguiente

ct_incremento:
    add     x21, x21, 1         // incrementos++
    add     x23, x23, 1         // racha_up++
    mov     x24, 0              // resetear racha_down
    // actualizar max_up si corresponde
    cmp     x23, x25
    ble     ct_siguiente
    mov     x25, x23
    b       ct_siguiente

ct_decremento:
    add     x22, x22, 1         // decrementos++
    add     x24, x24, 1         // racha_down++
    mov     x23, 0              // resetear racha_up
    // actualizar max_down si corresponde
    cmp     x24, x26
    ble     ct_siguiente
    mov     x26, x24

ct_siguiente:
    add     x20, x20, 1
    b       ct_loop

ct_fin:
    // Guardar resultados en memoria
    adr     x0, r_increments
    str     x21, [x0]
    adr     x0, r_decrements
    str     x22, [x0]
    adr     x0, r_max_up
    str     x25, [x0]
    adr     x0, r_max_down
    str     x26, [x0]
    adr     x0, r_accum_diff
    str     x27, [x0]

    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret


// ============================================================
// escribir_resultado
// Abre resultado_tendencia.txt y escribe todas las lineas
// con el formato exacto requerido por el proyecto.
// ============================================================
escribir_resultado:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]
    mov     x29, sp

    // Abrir/crear archivo de salida
    mov     x8, SYS_OPENAT
    mov     x0, AT_FDCWD
    adr     x1, fname_out
    mov     x2, O_WRONLY | O_CREAT | O_TRUNC
    mov     x3, PERM_644
    svc     0
    cmp     x0, 0
    blt     er_done
    mov     x19, x0             // x19 = fd salida

    // MODULE=ADVANCED_TREND
    bl      wr_module

    // TOTAL_VALUES=30
    bl      wr_total

    // INCREMENTS=<valor>
    adr     x0, lbl_inc_k
    mov     x1, lbl_inc_k_len
    bl      write_buf
    adr     x20, r_increments
    ldr     x0, [x20]
    bl      write_int_ln

    // DECREMENTS=<valor>
    adr     x0, lbl_dec_k
    mov     x1, lbl_dec_k_len
    bl      write_buf
    adr     x20, r_decrements
    ldr     x0, [x20]
    bl      write_int_ln

    // MAX_UP_STREAK=<valor>
    adr     x0, lbl_mup_k
    mov     x1, lbl_mup_k_len
    bl      write_buf
    adr     x20, r_max_up
    ldr     x0, [x20]
    bl      write_int_ln

    // MAX_DOWN_STREAK=<valor>
    adr     x0, lbl_mdn_k
    mov     x1, lbl_mdn_k_len
    bl      write_buf
    adr     x20, r_max_down
    ldr     x0, [x20]
    bl      write_int_ln

    // ACCUM_DIFF=<valor> (puede ser negativo)
    adr     x0, lbl_acc_k
    mov     x1, lbl_acc_k_len
    bl      write_buf
    adr     x20, r_accum_diff
    ldr     x0, [x20]
    bl      write_int_signed_ln

    // TREND=UP / DOWN / STABLE
    adr     x20, r_accum_diff
    ldr     x0, [x20]
    cmp     x0, 0
    bgt     wr_trend_up
    blt     wr_trend_down

    // STABLE
    adr     x0, lbl_trend_st
    mov     x1, lbl_trend_st_len
    bl      write_buf
    b       er_close

wr_trend_up:
    adr     x0, lbl_trend_up
    mov     x1, lbl_trend_up_len
    bl      write_buf
    b       er_close

wr_trend_down:
    adr     x0, lbl_trend_dn
    mov     x1, lbl_trend_dn_len
    bl      write_buf

er_close:
    mov     x8, SYS_CLOSE
    mov     x0, x19
    svc     0

er_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret


// ============================================================
// write_buf  - escribe x1 bytes desde x0 al fd x19
// ============================================================
write_buf:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x8, SYS_WRITE
    mov     x2, x1              // len
    mov     x1, x0              // buf
    mov     x0, x19             // fd
    svc     0
    ldp     x29, x30, [sp], #16
    ret


// ============================================================
// write_int_ln
// Convierte x0 (entero sin signo) a ASCII y escribe + '\n'
// Registros temporales: x9-x13 (caller-saved, seguros)
// ============================================================
write_int_ln:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x9,  buf_num        // puntero base del buffer
    add     x10, x9, #20        // empezamos desde el final
    mov     x11, x10            // x11 = cursor (retrocede)

    // Escribir '\n' primero (quedara al final del buffer)
    mov     w12, '\n'
    strb    w12, [x11]
    // NO decrementar aun

    // Caso especial: valor = 0
    cmp     x0, 0
    bne     wil_loop
    mov     w12, '0'
    sub     x11, x11, #1
    strb    w12, [x11]
    b       wil_write

wil_loop:
    cbz     x0, wil_write
    mov     x13, 10
    udiv    x12, x0, x13        // cociente
    msub    x12, x12, x13, x0   // resto = x0 - cociente*10
    add     w12, w12, '0'
    sub     x11, x11, #1
    strb    w12, [x11]
    udiv    x0, x0, x13
    b       wil_loop

wil_write:
    // longitud = (x10 - x11 + 1) incluyendo el \n
    sub     x1, x10, x11
    add     x1, x1, #1
    mov     x0, x11
    bl      write_buf

    ldp     x29, x30, [sp], #16
    ret


// ============================================================
// write_int_signed_ln
// Igual que write_int_ln pero maneja valores negativos.
// Si x0 < 0 escribe '-' primero, luego el valor absoluto.
// ============================================================
write_int_signed_ln:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    cmp     x0, 0
    bge     wisl_positivo

    // Escribir signo negativo
    adr     x1, neg_sign
    mov     x2, 1
    mov     x8, SYS_WRITE
    mov     x8, SYS_WRITE
    stp     x1, x2, [sp, #-16]!    // guardar temporalmente
    mov     x0, x19
    ldp     x1, x2, [sp], #16
    // forma correcta:
    neg     x0, x0              // x0 = abs(valor)
    // necesitamos escribir '-' antes de llamar write_int_ln
    // guardamos x0 y escribimos el signo
    str     x0, [sp, #-16]!
    mov     x8, SYS_WRITE
    mov     x0, x19
    adr     x1, neg_sign
    mov     x2, 1
    svc     0
    ldr     x0, [sp], #16

wisl_positivo:
    bl      write_int_ln

    ldp     x29, x30, [sp], #16
    ret


// ============================================================
// wr_module / wr_total - helpers para etiquetas fijas
// ============================================================
wr_module:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adr     x0, lbl_module
    mov     x1, lbl_module_len
    bl      write_buf
    ldp     x29, x30, [sp], #16
    ret

wr_total:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adr     x0, lbl_total
    mov     x1, lbl_total_len
    bl      write_buf
    ldp     x29, x30, [sp], #16
    ret

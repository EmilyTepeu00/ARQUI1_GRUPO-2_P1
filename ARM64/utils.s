// ============================================================
// utils.s - Biblioteca comun para modulos ARM64
// Basado en el patron del auxiliar (08_utils.s / 11_utils.s)
// ============================================================
// CONVENCION DE USO:
//   Antes de llamar a leer_datos:
//     x0 = numero de columna (1=ID,2=TEMP,3=HUM_AIRE,
//          4=HUM_SUELO_1,5=HUM_SUELO_2,6=LUZ,7=GAS)
//   Despues de leer_datos:
//     datos[]  = arreglo con los 30 valores leidos
//     x0       = cantidad de filas leidas
// ============================================================

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

// ============================================================
.section .data

nombre_csv:
    .asciz "lecturas.csv"

nombre_salida_buf:
    .skip 64

err_open_msg:
    .ascii "Error: no se pudo abrir lecturas.csv\n"
    .equ err_open_len, . - err_open_msg

// ============================================================
.section .bss

// buffer grande — lee el CSV entero de una vez (igual que el aux)
csv_buffer:     .skip 4096
fd_csv:         .skip 8
buffer_num:     .skip 32

// arreglo publico con los 30 datos extraidos
datos:          .skip 240       // 30 x 8 bytes
.global datos

// ============================================================
.section .text

.global leer_datos
.global escribir_archivo
.global int_a_ascii
.global ascii_a_int
.global datos

// ============================================================
// FUNCION: leer_datos
// Lee lecturas.csv completo en buffer y extrae columna dada.
// Entrada:  x0 = numero de columna (1-based, 1=ID, 2=TEMP...)
// Salida:   datos[] lleno, x0 = filas leidas
// Igual al patron de 08_utils.s / 11_utils.s del aux
// ============================================================
leer_datos:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]

    mov x11, x0             // x11 = columna objetivo

    // --- abrir archivo ---
    mov x8,  SYS_OPENAT
    mov x0,  AT_FDCWD
    adr x1,  nombre_csv
    mov x2,  O_RDONLY
    mov x3,  #0
    svc #0

    cmp x0, #0
    blt leer_datos_error_open

    mov x19, x0             // x19 = fd

    // --- leer TODO el archivo de una vez en csv_buffer ---
    mov x8,  SYS_READ
    mov x0,  x19
    adr x1,  csv_buffer
    mov x2,  #4096
    svc #0

    // cerrar archivo
    mov x8,  SYS_CLOSE
    mov x0,  x19
    svc #0

    // x21 = puntero actual dentro del buffer
    adr x21, csv_buffer
    mov x22, #0             // contador de filas
    mov x5,  #10            // base para atoi

    // --- saltar cabecera (primera linea) ---
leer_skip_header:
    ldrb w23, [x21], #1
    cmp w23, #10            // '\n'
    beq leer_process_line
    cmp w23, '$'
    beq leer_done
    cmp w23, #0
    beq leer_done
    b leer_skip_header

    // --- procesar cada linea de datos ---
leer_process_line:
    cmp x22, #30
    bge leer_done

    mov x12, #1             // columna actual = 1

leer_find_column:
    cmp x12, x11
    beq leer_read_column

    // saltar hasta la proxima coma, '\n', '$' o '\0'
leer_skip_to_comma:
    ldrb w23, [x21], #1
    cmp w23, '$'
    beq leer_done
    cmp w23, #10
    beq leer_process_line
    cmp w23, #0
    beq leer_done
    cmp w23, ','
    bne leer_skip_to_comma

    add x12, x12, #1
    b leer_find_column

    // --- leer el valor de la columna con atoi ---
leer_read_column:
    mov x10, #0             // resultado = 0
    mov x7,  #0             // bandera digito leido

leer_atoi_loop:
    ldrb w23, [x21], #1

    cmp w23, ','
    beq leer_atoi_done
    cmp w23, #10
    beq leer_atoi_done
    cmp w23, '$'
    beq leer_atoi_done
    cmp w23, #0
    beq leer_atoi_done

    // ignorar punto decimal — igual que 07_atoi_b.s del aux
    cmp w23, '0'
    blt leer_atoi_loop
    cmp w23, '9'
    bgt leer_atoi_loop

    sub w23, w23, '0'
    mov x4,  x10
    mul x10, x4, x5
    add x10, x10, x23
    mov x7,  #1
    b leer_atoi_loop

leer_atoi_done:
    // guardar en datos[x22]
    adr x24, datos
    str x10, [x24, x22, lsl #3]
    add x22, x22, #1

    // si termino en '\n', ir a siguiente linea
    cmp w23, #10
    beq leer_process_line
    cmp w23, '$'
    beq leer_done
    cmp w23, #0
    beq leer_done

    // saltar resto de la linea
leer_skip_rest:
    ldrb w23, [x21], #1
    cmp w23, '$'
    beq leer_done
    cmp w23, #10
    beq leer_process_line
    cmp w23, #0
    beq leer_done
    b leer_skip_rest

leer_done:
    mov x0, x22

    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

leer_datos_error_open:
    mov x8,  SYS_WRITE
    mov x0,  #2
    adr x1,  err_open_msg
    mov x2,  err_open_len
    svc #0
    mov x0,  #0
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

// ============================================================
// FUNCION: escribir_archivo
// x0 = puntero al nombre del archivo
// x1 = puntero al contenido
// x2 = bytes a escribir
// ============================================================
escribir_archivo:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]

    mov x19, x1
    mov x20, x2
    mov x21, x0

    mov x8,  SYS_OPENAT
    mov x0,  AT_FDCWD
    mov x1,  x21
    mov x2,  O_WRONLY | O_CREAT | O_TRUNC
    mov x3,  PERM_644
    svc #0

    cmp x0, #0
    blt escribir_error

    mov x22, x0

    mov x8,  SYS_WRITE
    mov x0,  x22
    mov x1,  x19
    mov x2,  x20
    svc #0

    mov x0,  x22
    mov x8,  SYS_CLOSE
    svc #0

    mov x0,  #0
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

escribir_error:
    mov x0,  -1
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

// ============================================================
// FUNCION: int_a_ascii
// x0 = numero, x1 = buffer destino
// ============================================================
int_a_ascii:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]

    mov x19, x0
    mov x20, x1

    cbnz x19, int_a_ascii_normal
    mov w2, '0'
    strb w2, [x20]
    strb wzr, [x20, #1]
    b int_a_ascii_fin

int_a_ascii_normal:
    adr x2,  buffer_num
    mov x3,  #0

int_a_ascii_extraer:
    cbz x19, int_a_ascii_invertir
    mov x4,  #10
    udiv x5, x19, x4
    msub x6, x5, x4, x19
    add w6,  w6,  '0'
    strb w6, [x2, x3]
    add x3,  x3,  #1
    mov x19, x5
    b int_a_ascii_extraer

int_a_ascii_invertir:
    mov x4, #0

int_a_ascii_inv_loop:
    cbz x3, int_a_ascii_nulo
    sub x3,  x3, #1
    ldrb w5, [x2, x3]
    strb w5, [x20, x4]
    add x4,  x4, #1
    b int_a_ascii_inv_loop

int_a_ascii_nulo:
    strb wzr, [x20, x4]

int_a_ascii_fin:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// ============================================================
// FUNCION: ascii_a_int
// x0 = puntero al texto
// retorna x0 = numero
// ============================================================
ascii_a_int:
    mov x1, #0

ascii_a_int_loop:
    ldrb w2, [x0]
    cmp w2, '0'
    blt ascii_a_int_fin
    cmp w2, '9'
    bgt ascii_a_int_fin
    mov x3, #10
    mul x1, x1, x3
    sub w2, w2, '0'
    add x1, x1, x2
    add x0, x0, #1
    b ascii_a_int_loop

ascii_a_int_fin:
    mov x0, x1
    ret

// ---- Fin utils.s ------------------------------------------

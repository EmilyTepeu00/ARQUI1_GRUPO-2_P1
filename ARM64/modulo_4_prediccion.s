// modulo_4_prediccion.s
// Rutina ARM64 - Prediccion Lineal Simple
// Variable: TEMP (columna 1)
// Salida: resultado_prediccion.txt
//
// DIF = XFINAL - XINICIAL
// PROMEDIO_CAMBIO = DIF / (N-1)
// PREDICCION = XFINAL + PROMEDIO_CAMBIO
//
// Compilar:
//   aarch64-linux-gnu-as utils.s -o utils.o
//   aarch64-linux-gnu-as modulo_4_prediccion.s -o modulo_4_prediccion.o
//   aarch64-linux-gnu-ld utils.o modulo_4_prediccion.o -o modulo_4_prediccion
//
// Ejecutar:
//   qemu-aarch64 ./modulo_4_prediccion
//   cat resultado_prediccion.txt

.equ SYS_OPENAT,  56
.equ SYS_CLOSE,   57
.equ SYS_READ,    63
.equ SYS_WRITE,   64
.equ SYS_EXIT,    93
.equ AT_FDCWD,   -100
.equ O_WRONLY,    1
.equ O_CREAT,     64
.equ O_TRUNC,     512
.equ PERM_644,    0644
.equ COL_OBJETIVO, 1
.equ N_DATOS,      30

.section .data

archivo_salida:  .asciz "resultado_prediccion.txt"

str_module:      .ascii "MODULE=PREDICTION\n"
.equ str_module_len, . - str_module
str_total:       .ascii "TOTAL_VALUES=30\n"
.equ str_total_len, . - str_total
str_inicial:     .ascii "INITIAL_VALUE="
.equ str_inicial_len, . - str_inicial
str_final:       .ascii "FINAL_VALUE="
.equ str_final_len, . - str_final
str_diff:        .ascii "TOTAL_DIFF="
.equ str_diff_len, . - str_diff
str_avg:         .ascii "AVG_CHANGE="
.equ str_avg_len, . - str_avg
str_next:        .ascii "NEXT_VALUE="
.equ str_next_len, . - str_next
str_newline:     .ascii "\n"
.equ str_newline_len, . - str_newline

.section .bss
buf_num:  .skip 32
fd_out:   .skip 8

.section .text
.global _start

_start:
    bl abrir_archivo
    cmp x0, 0
    blt fin_error

    mov x1, COL_OBJETIVO
    bl leer_datos

    // x0 = datos[0] (inicial)
    adr x19, datos
    ldr x20, [x19]          // x_inicial = datos[0]

    // x_final = datos[29]
    add x21, x19, #(29*8)
    ldr x21, [x21]          // x_final = datos[29]

    // dif = final - inicial
    sub x22, x21, x20       // x22 = dif

    // promedio_cambio = dif / (N-1) = dif / 29
    mov x23, #29
    sdiv x24, x22, x23      // x24 = promedio (entero)

    // prediccion = final + promedio
    add x25, x21, x24       // x25 = prediccion

    // abrir archivo salida
    mov x8,  SYS_OPENAT
    mov x0,  AT_FDCWD
    adr x1,  archivo_salida
    mov x2,  #(O_WRONLY | O_CREAT | O_TRUNC)
    mov x3,  PERM_644
    svc 0
    adr x10, fd_out
    str x0,  [x10]

    // escribir MODULE
    mov x1, x0
    adr x2,  str_module
    mov x3,  str_module_len
    bl  _escribir_buf

    ldr x1,  [x10]
    adr x2,  str_total
    mov x3,  str_total_len
    bl  _escribir_buf

    // INITIAL_VALUE
    ldr x1,  [x10]
    adr x2,  str_inicial
    mov x3,  str_inicial_len
    bl  _escribir_buf

    ldr x1,  [x10]
    mov x0,  x20
    bl  _escribir_int

    // FINAL_VALUE
    ldr x1,  [x10]
    adr x2,  str_final
    mov x3,  str_final_len
    bl  _escribir_buf

    ldr x1,  [x10]
    mov x0,  x21
    bl  _escribir_int

    // TOTAL_DIFF
    ldr x1,  [x10]
    adr x2,  str_diff
    mov x3,  str_diff_len
    bl  _escribir_buf

    ldr x1,  [x10]
    mov x0,  x22
    bl  _escribir_int

    // AVG_CHANGE
    ldr x1,  [x10]
    adr x2,  str_avg
    mov x3,  str_avg_len
    bl  _escribir_buf

    ldr x1,  [x10]
    mov x0,  x24
    bl  _escribir_int

    // NEXT_VALUE
    ldr x1,  [x10]
    adr x2,  str_next
    mov x3,  str_next_len
    bl  _escribir_buf

    ldr x1,  [x10]
    mov x0,  x25
    bl  _escribir_int

    // cerrar salida
    ldr x0,  [x10]
    mov x8,  SYS_CLOSE
    svc 0

    bl cerrar_archivo
    mov x8,  SYS_EXIT
    mov x0,  0
    svc 0

fin_error:
    mov x8,  SYS_EXIT
    mov x0,  1
    svc 0

// Escribe buffer directo al fd en x1
_escribir_buf:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x0,  x1
    mov x8,  SYS_WRITE
    svc 0
    ldp x29, x30, [sp], #16
    ret

// Convierte x0 (entero) a ASCII y lo escribe al fd x1
_escribir_int:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x1,  [sp, #16]

    adr x2,  buf_num
    add x3,  x2, #30
    mov x4,  #'\n'
    strb w4, [x3]
    sub x3,  x3, #1

    cmp x0,  0
    bge _wi_pos
    neg x0,  x0
    mov x9,  1
    b   _wi_conv
_wi_pos:
    mov x9,  0

_wi_conv:
    mov x5,  #10
_wi_loop:
    udiv x6, x0, x5
    msub x7, x6, x5, x0
    add  x7, x7, #'0'
    strb w7, [x3]
    sub  x3, x3, #1
    mov  x0, x6
    cbnz x0, _wi_loop

    cmp x9,  #1
    bne _wi_write
    mov x7,  #'-'
    strb w7, [x3]
    sub x3,  x3, #1

_wi_write:
    add x3,  x3, #1
    adr x2,  buf_num
    add x4,  x2, #31
    sub x5,  x4, x3

    ldr x1,  [sp, #16]
    mov x8,  SYS_WRITE
    mov x0,  x1
    mov x2,  x3
    svc 0

    ldp x29, x30, [sp], #48
    ret

@ ============================================================
@ utils.s - Biblioteca comun para modulos ARM64
@ Proyecto: Invernadero Inteligente IoT
@ ============================================================
@ FUNCIONES DISPONIBLES:
@   - abrir_archivo   : abre lecturas.csv para lectura
@   - cerrar_archivo  : cierra el archivo
@   - leer_datos      : lee 30 filas y extrae una columna
@   - escribir_archivo: escribe resultados en un .txt
@   - int_a_ascii     : convierte entero a texto ASCII
@   - ascii_a_int     : convierte texto ASCII a entero
@ ============================================================

@ ---- Llamadas al sistema Linux AArch64 --------------------
.equ SYS_OPENAT,  56
.equ SYS_CLOSE,   57
.equ SYS_READ,    63
.equ SYS_WRITE,   64
.equ AT_FDCWD,   -100
.equ O_RDONLY,    0
.equ O_WRONLY,    1
.equ O_CREAT,     64
.equ O_TRUNC,     512
.equ PERM_644,    0644

@ ============================================================
@ SECCION DE DATOS
@ ============================================================
.section .data

nombre_csv:
    .asciz "lecturas.csv"

error_apertura_msg:
    .ascii "Error: no se pudo abrir lecturas.csv\n"
    .equ error_apertura_msg_len, . - error_apertura_msg

@ ============================================================
@ SECCION BSS
@ ============================================================
.section .bss

buffer_linea:   .skip 200
datos:          .skip 240       @ 30 enteros x 8 bytes
fd_entrada:     .skip 8
fd_salida:      .skip 8
buffer_num:     .skip 32

@ ============================================================
@ SECCION DE CODIGO
@ ============================================================
.section .text

.global abrir_archivo
.global cerrar_archivo
.global leer_datos
.global escribir_archivo
.global int_a_ascii
.global ascii_a_int

@ ============================================================
@ FUNCION: abrir_archivo
@ Abre lecturas.csv en modo solo lectura.
@ Retorna: x0 = descriptor de archivo (negativo si error)
@ ============================================================
abrir_archivo:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    mov x8,  SYS_OPENAT
    mov x0,  AT_FDCWD
    adr x1,  nombre_csv
    mov x2,  O_RDONLY
    mov x3,  0
    svc 0

    cmp x0,  0
    blt abrir_error

    @ Guardar descriptor en fd_entrada
    adr x1,  fd_entrada
    str x0,  [x1]

    ldp x29, x30, [sp], #16
    ret

abrir_error:
    @ Escribir mensaje de error en stderr
    mov x8,  SYS_WRITE
    mov x0,  2
    adr x1,  error_apertura_msg
    mov x2,  error_apertura_msg_len
    svc 0

    mov x0,  -1
    ldp x29, x30, [sp], #16
    ret

@ ============================================================
@ FUNCION: cerrar_archivo
@ Cierra el archivo cuyo descriptor esta en x0.
@ ============================================================
cerrar_archivo:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    mov x8,  SYS_CLOSE
    svc 0

    ldp x29, x30, [sp], #16
    ret

@ ============================================================
@ FUNCION: leer_datos
@ Lee lecturas.csv y extrae 30 valores de la columna dada.
@ Parametro: x0 = numero de columna (0=ID,1=TEMP,2=HUM_AIRE,
@            3=HUM_SUELO_1,4=HUM_SUELO_2,5=LUZ,6=GAS)
@ Resultado: valores en el arreglo 'datos', x0=filas leidas
@ ============================================================
leer_datos:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]

    mov x19, x0             @ columna objetivo

    @ Abrir archivo
    bl  abrir_archivo
    cmp x0,  0
    blt leer_datos_error
    mov x22, x0             @ descriptor del archivo

    mov x20, 0              @ contador de filas
    adr x21, datos          @ puntero base al arreglo

    @ Saltar cabecera
    mov x0,  x22
    adr x1,  buffer_linea
    mov x2,  200
    bl  utils_leer_linea

leer_datos_loop:
    cmp x20, 30
    bge leer_datos_listo

    @ Leer siguiente linea
    mov x0,  x22
    adr x1,  buffer_linea
    mov x2,  200
    bl  utils_leer_linea

    @ EOF o error
    cmp x0,  0
    ble leer_datos_listo

    @ Verificar marcador '$'
    adr x9,  buffer_linea
    ldrb w10, [x9]
    cmp w10, '$'
    beq leer_datos_listo

    @ Extraer columna
    adr x0,  buffer_linea
    mov x1,  x19
    bl  utils_extraer_columna

    @ Guardar en datos[x20]
    str x0,  [x21, x20, lsl #3]
    add x20, x20, 1
    b   leer_datos_loop

leer_datos_listo:
    mov x0,  x22
    bl  cerrar_archivo
    mov x0,  x20

    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

leer_datos_error:
    mov x0,  0
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

@ ============================================================
@ FUNCION INTERNA: utils_leer_linea
@ Lee caracteres hasta encontrar '\n' o EOF.
@ x0 = descriptor, x1 = buffer, x2 = tamanio maximo
@ Retorna x0 = cantidad de caracteres leidos (0 = EOF)
@ ============================================================
utils_leer_linea:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]

    mov x19, x0             @ descriptor
    mov x20, x1             @ buffer
    mov x3,  0              @ contador

utils_leer_linea_loop:
    mov x8,  SYS_READ
    mov x0,  x19
    add x1,  x20, x3
    mov x2,  1
    svc 0

    cmp x0,  0
    ble utils_leer_linea_fin

    ldrb w1, [x20, x3]
    cmp w1,  10             @ '\n'
    beq utils_leer_linea_fin

    add x3,  x3,  1
    cmp x3,  199
    bge utils_leer_linea_fin
    b   utils_leer_linea_loop

utils_leer_linea_fin:
    strb wzr, [x20, x3]
    mov x0,  x3

    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

@ ============================================================
@ FUNCION INTERNA: utils_extraer_columna
@ Extrae el valor numerico de la columna N de una linea CSV.
@ x0 = puntero a la linea, x1 = numero de columna
@ Retorna x0 = valor numerico
@ ============================================================
utils_extraer_columna:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]

    mov x19, x0             @ puntero a la linea
    mov x20, x1             @ columna objetivo
    mov x2,  0              @ columna actual

utils_ec_buscar:
    cmp x2,  x20
    beq utils_ec_encontrada

utils_ec_buscar_coma:
    ldrb w3, [x19]
    cmp w3,  0
    beq utils_ec_no_encontrada
    cmp w3,  44             @ ','
    beq utils_ec_siguiente_col
    add x19, x19, 1
    b   utils_ec_buscar_coma

utils_ec_siguiente_col:
    add x19, x19, 1         @ saltar la coma
    add x2,  x2,  1
    b   utils_ec_buscar

utils_ec_encontrada:
    mov x0,  x19
    bl  ascii_a_int

    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

utils_ec_no_encontrada:
    mov x0,  0
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

@ ============================================================
@ FUNCION: ascii_a_int
@ Convierte texto "123" al numero entero 123.
@ Parametro: x0 = puntero al texto
@ Retorna:   x0 = numero entero
@ ============================================================
ascii_a_int:
    mov x1,  0              @ resultado = 0

ascii_a_int_loop:
    ldrb w2, [x0]
    cmp w2,  48             @ '0'
    blt ascii_a_int_fin
    cmp w2,  57             @ '9'
    bgt ascii_a_int_fin

    mov x3,  10
    mul x1,  x1, x3
    sub w2,  w2, 48
    add x1,  x1, x2

    add x0,  x0, 1
    b   ascii_a_int_loop

ascii_a_int_fin:
    mov x0,  x1
    ret

@ ============================================================
@ FUNCION: int_a_ascii
@ Convierte el numero 123 al texto "123".
@ Parametros: x0 = numero, x1 = buffer destino
@ ============================================================
int_a_ascii:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]

    mov x19, x0             @ numero
    mov x20, x1             @ buffer destino

    @ Caso especial: numero es 0
    cbnz x19, int_a_ascii_normal
    mov w2,  48             @ '0'
    strb w2, [x20]
    strb wzr, [x20, #1]
    b   int_a_ascii_fin

int_a_ascii_normal:
    adr x2,  buffer_num
    mov x3,  0              @ contador de digitos

int_a_ascii_extraer:
    cbz x19, int_a_ascii_invertir
    mov x4,  10
    udiv x5, x19, x4
    msub x6, x5, x4, x19   @ x6 = x19 % 10
    add w6,  w6,  48        @ a ASCII
    strb w6, [x2, x3]
    add x3,  x3,  1
    mov x19, x5
    b   int_a_ascii_extraer

int_a_ascii_invertir:
    mov x4,  0

int_a_ascii_inv_loop:
    cbz x3,  int_a_ascii_nulo
    sub x3,  x3,  1
    ldrb w5, [x2, x3]
    strb w5, [x20, x4]
    add x4,  x4,  1
    b   int_a_ascii_inv_loop

int_a_ascii_nulo:
    strb wzr, [x20, x4]

int_a_ascii_fin:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

@ ============================================================
@ FUNCION: escribir_archivo
@ Abre/crea un archivo .txt y escribe contenido.
@ Parametros:
@   x0 = puntero al nombre del archivo
@   x1 = puntero al contenido
@   x2 = cantidad de bytes a escribir
@ ============================================================
escribir_archivo:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]

    mov x19, x1             @ contenido
    mov x20, x2             @ tamanio
    mov x21, x0             @ nombre del archivo

    @ Abrir/crear archivo de salida
    mov x8,  SYS_OPENAT
    mov x0,  AT_FDCWD
    mov x1,  x21
    mov x2,  O_WRONLY | O_CREAT | O_TRUNC
    mov x3,  PERM_644
    svc 0

    cmp x0,  0
    blt escribir_archivo_error
    mov x22, x0             @ descriptor de salida

    @ Escribir contenido
    mov x8,  SYS_WRITE
    mov x0,  x22
    mov x1,  x19
    mov x2,  x20
    svc 0

    @ Cerrar archivo
    mov x0,  x22
    bl  cerrar_archivo

    mov x0,  0
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

escribir_archivo_error:
    mov x0,  -1
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

@ ---- Fin utils.s ------------------------------------------
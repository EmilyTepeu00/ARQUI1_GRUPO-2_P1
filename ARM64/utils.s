// ============================================================
// utils.s - Biblioteca común para módulos ARM64
// Proyecto: Invernadero Inteligente IoT
// ============================================================
// Esta biblioteca contiene funciones que todos los módulos
// comparten para no repetir código.
//
// FUNCIONES DISPONIBLES:
//   - abrir_archivo     : abre lecturas.csv para lectura
//   - cerrar_archivo    : cierra el archivo
//   - leer_datos        : lee las 30 filas y extrae una columna
//   - escribir_archivo  : escribe resultados en un .txt
//   - int_a_ascii       : convierte número entero a texto
// ============================================================

.section .data

// Nombre del archivo de entrada (siempre el mismo)
nombre_csv:
    .asciz "lecturas.csv"

// Mensaje de error si no abre el archivo
error_msg:
    .asciz "Error: no se pudo abrir lecturas.csv\n"
error_msg_len = . - error_msg

// Buffer para leer líneas del CSV (200 caracteres máximo por línea)
.comm buffer_linea, 200, 8

// Arreglo donde se guardan los 30 datos extraídos
// Cada número ocupa 8 bytes (64 bits), 30 números = 240 bytes
.comm datos, 240, 8

// Variable para guardar el descriptor del archivo abierto
.comm fd_entrada, 8, 8

// Variable para guardar el descriptor del archivo de salida
.comm fd_salida, 8, 8

// Buffer temporal para conversiones de número a texto
.comm buffer_num, 32, 8

// ============================================================
.section .text
.global abrir_archivo
.global cerrar_archivo
.global leer_datos
.global escribir_archivo
.global int_a_ascii
.global ascii_a_int

// ============================================================
// FUNCIÓN: abrir_archivo
// ¿Qué hace? Abre el archivo lecturas.csv
// ¿Cómo usarla?
//   bl abrir_archivo
//   (si x0 es negativo después, hubo un error)
// ============================================================
abrir_archivo:
    // Guardar el registro de retorno (lr) para poder volver
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // syscall open(filename, O_RDONLY, 0)
    // x8 = número de syscall (openat = 56 en ARM64)
    // x0 = AT_FDCWD (-100) significa directorio actual
    // x1 = nombre del archivo
    // x2 = flags: 0 = solo lectura
    mov x8, #56             // número de syscall openat
    mov x0, #-100           // AT_FDCWD (directorio actual)
    adr x1, nombre_csv      // dirección del nombre del archivo
    mov x2, #0              // O_RDONLY (solo lectura)
    mov x3, #0              // modo (no aplica para lectura)
    svc #0                  // llamada al sistema operativo

    // x0 ahora tiene el "descriptor de archivo" (un número)
    // Si es negativo, hubo un error
    cmp x0, #0
    blt .error_apertura     // si x0 < 0, saltar a error

    // Guardar el descriptor para usarlo después
    adr x1, fd_entrada
    str x0, [x1]

    // Salir sin error (x0 queda con el descriptor)
    ldp x29, x30, [sp], #16
    ret

.error_apertura:
    // Imprimir mensaje de error
    mov x8, #64             // syscall write
    mov x0, #2              // stderr
    adr x1, error_msg
    mov x2, #error_msg_len
    svc #0

    mov x0, #-1             // retornar -1 como señal de error
    ldp x29, x30, [sp], #16
    ret

// ============================================================
// FUNCIÓN: cerrar_archivo
// ¿Qué hace? Cierra el archivo abierto
// ¿Cómo usarla?
//   mov x0, fd  // descriptor del archivo
//   bl cerrar_archivo
// ============================================================
cerrar_archivo:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // syscall close(fd)
    mov x8, #57             // número de syscall close
    // x0 ya tiene el descriptor del archivo
    svc #0

    ldp x29, x30, [sp], #16
    ret

// ============================================================
// FUNCIÓN: leer_datos
// ¿Qué hace? Lee lecturas.csv y extrae los 30 valores
//            de la columna indicada
// Parámetro de entrada:
//   x0 = número de columna a extraer
//        0=ID, 1=TEMP, 2=HUM_AIRE, 3=HUM_SUELO_1,
//        4=HUM_SUELO_2, 5=LUZ, 6=GAS
// Resultado:
//   Los 30 valores quedan guardados en el arreglo 'datos'
// ============================================================
leer_datos:
    stp x29, x30, [sp, #-48]!
    mov x29, sp

    // Guardar registros que vamos a usar
    str x19, [sp, #16]      // x19 = columna objetivo
    str x20, [sp, #24]      // x20 = contador de filas
    str x21, [sp, #32]      // x21 = puntero al arreglo datos
    str x22, [sp, #40]      // x22 = descriptor del archivo

    mov x19, x0             // guardar número de columna

    // Abrir el archivo
    bl abrir_archivo
    cmp x0, #0
    blt .leer_error
    mov x22, x0             // guardar descriptor

    // Inicializar contador de filas en 0
    mov x20, #0

    // Apuntar al inicio del arreglo datos
    adr x21, datos

    // --- Saltar la primera línea (encabezado del CSV) ---
    mov x0, x22
    adr x1, buffer_linea
    mov x2, #200
    bl .leer_linea_completa

.loop_filas:
    // ¿Ya leímos 30 filas?
    cmp x20, #30
    bge .leer_listo         // si ya son 30, terminar

    // Leer una línea del archivo
    mov x0, x22
    adr x1, buffer_linea
    mov x2, #200
    bl .leer_linea_completa

    // ¿Llegamos al final del archivo?
    cmp x0, #0
    ble .leer_listo

    // Extraer la columna que nos interesa
    adr x0, buffer_linea    // x0 = inicio de la línea
    mov x1, x19             // x1 = número de columna
    bl .extraer_columna     // resultado en x0

    // Guardar el valor en el arreglo datos
    str x0, [x21, x20, lsl #3]  // datos[x20] = valor

    // Incrementar contador de filas
    add x20, x20, #1

    b .loop_filas           // siguiente fila

.leer_listo:
    // Cerrar el archivo
    mov x0, x22
    bl cerrar_archivo

    mov x0, x20             // retornar cuántos datos se leyeron

    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldr x21, [sp, #32]
    ldr x22, [sp, #40]
    ldp x29, x30, [sp], #48
    ret

.leer_error:
    mov x0, #0
    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldr x21, [sp, #32]
    ldr x22, [sp, #40]
    ldp x29, x30, [sp], #48
    ret

// ============================================================
// FUNCIÓN INTERNA: .leer_linea_completa
// Lee caracteres uno por uno hasta encontrar '\n' o EOF
// x0 = descriptor archivo, x1 = buffer, x2 = tamaño máximo
// Retorna en x0: cantidad de caracteres leídos (0 = EOF)
// ============================================================
.leer_linea_completa:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    str x20, [sp, #24]

    mov x19, x0             // descriptor
    mov x20, x1             // buffer
    mov x3, #0              // contador de caracteres

.loop_char:
    // Leer 1 byte del archivo
    mov x8, #63             // syscall read
    mov x0, x19
    add x1, x20, x3        // posición actual en buffer
    mov x2, #1              // leer 1 byte
    svc #0

    // ¿Se leyó algo?
    cmp x0, #0
    ble .fin_linea          // EOF o error

    // ¿Es un salto de línea '\n'?
    ldrb w1, [x20, x3]
    cmp w1, #10             // ASCII de '\n' es 10
    beq .fin_linea

    // Siguiente carácter
    add x3, x3, #1

    // ¿Buffer lleno?
    cmp x3, #199
    bge .fin_linea

    b .loop_char

.fin_linea:
    // Poner terminador nulo al final
    strb wzr, [x20, x3]
    mov x0, x3              // retornar cantidad leída

    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret

// ============================================================
// FUNCIÓN INTERNA: .extraer_columna
// Extrae el valor numérico de la columna N de una línea CSV
// x0 = puntero a la línea (texto), x1 = número de columna
// Retorna en x0: el valor numérico de esa columna
// ============================================================
.extraer_columna:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    str x20, [sp, #24]

    mov x19, x0             // puntero a la línea
    mov x20, x1             // columna objetivo
    mov x2, #0              // columna actual = 0

.buscar_columna:
    // ¿Ya estamos en la columna correcta?
    cmp x2, x20
    beq .columna_encontrada

    // Buscar la próxima coma
.buscar_coma:
    ldrb w3, [x19]          // leer carácter actual
    cmp w3, #0              // ¿fin de cadena?
    beq .columna_no_encontrada
    cmp w3, #44             // ASCII de ',' es 44
    beq .siguiente_columna
    add x19, x19, #1        // avanzar un carácter
    b .buscar_coma

.siguiente_columna:
    add x19, x19, #1        // saltar la coma
    add x2, x2, #1          // incrementar columna actual
    b .buscar_columna

.columna_encontrada:
    // x19 apunta al inicio del número en texto
    // Convertir de ASCII a entero
    mov x0, x19
    bl ascii_a_int          // resultado en x0

    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret

.columna_no_encontrada:
    mov x0, #0
    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret

// ============================================================
// FUNCIÓN: ascii_a_int
// ¿Qué hace? Convierte texto "123" al número 123
// Parámetro: x0 = puntero al texto con el número
// Resultado: x0 = el número entero
//
// Ejemplo: si x0 apunta a "28\0", retorna 28
// ============================================================
ascii_a_int:
    mov x1, #0              // resultado acumulado = 0

.loop_ascii:
    ldrb w2, [x0]           // leer carácter actual
    cmp w2, #48             // ASCII '0' = 48
    blt .fin_ascii          // si es menor que '0', terminar
    cmp w2, #57             // ASCII '9' = 57
    bgt .fin_ascii          // si es mayor que '9', terminar

    // resultado = resultado * 10 + (caracter - '0')
    mov x3, #10
    mul x1, x1, x3          // resultado * 10
    sub w2, w2, #48         // convertir ASCII a dígito
    add x1, x1, x2          // sumar el dígito

    add x0, x0, #1          // siguiente carácter
    b .loop_ascii

.fin_ascii:
    mov x0, x1              // retornar el número
    ret

// ============================================================
// FUNCIÓN: int_a_ascii
// ¿Qué hace? Convierte el número 123 al texto "123"
// Parámetros:
//   x0 = el número a convertir
//   x1 = puntero al buffer donde escribir el texto
// Resultado: el texto queda en el buffer apuntado por x1
// ============================================================
int_a_ascii:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    str x20, [sp, #24]

    mov x19, x0             // número a convertir
    mov x20, x1             // buffer de destino

    // Caso especial: el número es 0
    cmp x19, #0
    bne .convertir_normal
    mov w2, #48             // ASCII '0'
    strb w2, [x20]
    mov w2, #0
    strb w2, [x20, #1]
    b .fin_int_ascii

.convertir_normal:
    // Usamos un buffer temporal para construir al revés
    adr x2, buffer_num
    mov x3, #0              // contador de dígitos

.extraer_digitos:
    cmp x19, #0
    beq .invertir_digitos

    // dígito = número % 10
    mov x4, #10
    udiv x5, x19, x4        // x5 = número / 10
    msub x6, x5, x4, x19   // x6 = número - (x5 * 10) = número % 10

    add w6, w6, #48         // convertir a ASCII
    strb w6, [x2, x3]       // guardar en buffer temporal
    add x3, x3, #1          // siguiente posición

    mov x19, x5             // número = número / 10
    b .extraer_digitos

.invertir_digitos:
    // Los dígitos quedaron al revés, invertir al buffer destino
    mov x4, #0              // índice del destino

.loop_invertir:
    cmp x3, #0
    beq .agregar_nulo
    sub x3, x3, #1
    ldrb w5, [x2, x3]
    strb w5, [x20, x4]
    add x4, x4, #1
    b .loop_invertir

.agregar_nulo:
    strb wzr, [x20, x4]     // terminar con '\0'

.fin_int_ascii:
    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret

// ============================================================
// FUNCIÓN: escribir_archivo
// ¿Qué hace? Abre un archivo .txt y escribe contenido
// Parámetros:
//   x0 = puntero al nombre del archivo (ej: "resultado.txt")
//   x1 = puntero al contenido a escribir
//   x2 = cantidad de bytes a escribir
// ============================================================
escribir_archivo:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    str x20, [sp, #24]

    mov x19, x1             // guardar contenido
    mov x20, x2             // guardar tamaño

    // Abrir (o crear) el archivo de salida
    // flags: O_WRONLY(1) | O_CREAT(64) | O_TRUNC(512) = 577
    mov x8, #56             // openat
    mov x0, #-100           // AT_FDCWD
    // x0 (nombre) ya viene como parámetro... necesitamos guardarlo
    // Ajuste: el nombre viene en x0, lo movemos a x1
    mov x1, x0
    mov x0, #-100
    mov x2, #577            // O_WRONLY | O_CREAT | O_TRUNC
    mov x3, #0644           // permisos del archivo
    svc #0

    cmp x0, #0
    blt .escribir_error

    // Escribir el contenido
    mov x3, x0              // guardar descriptor
    mov x8, #64             // syscall write
    mov x0, x3
    mov x1, x19             // contenido
    mov x2, x20             // tamaño
    svc #0

    // Cerrar el archivo
    mov x0, x3
    bl cerrar_archivo

    mov x0, #0              // éxito

    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret

.escribir_error:
    mov x0, #-1
    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret


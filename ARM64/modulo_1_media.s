// ============================================================
// modulo_1_media.s
// Rutina ARM64 - Media Aritmetica Ponderada
// Proyecto: Invernadero Inteligente IoT - ACYE1
// Integrante 1
//
// Variable analizada : TEMP (columna 1 del CSV)
// Entrada            : lecturas.csv
// Salida             : resultado_media.txt
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

// ---- Numeros de syscall Linux AArch64 ---------------------
.equ SYS_OPENAT, 56
.equ SYS_CLOSE,  57
.equ SYS_READ,   63
.equ SYS_WRITE,  64
.equ SYS_EXIT,   93

// ---- Flags para abrir/crear archivos ----------------------
.equ AT_FDCWD,   -100
.equ O_RDONLY,   0
.equ O_WRONLY,   1
.equ O_CREAT,    64
.equ O_TRUNC,    512
.equ PERM_644,   0644

// ---- Constantes del modulo --------------------------------
.equ COL_TEMP,   1      // columna TEMP en el CSV (0-indexada)
.equ N,          30     // cantidad de datos


// ============================================================
// SECCION DE DATOS - strings fijos del archivo de salida
// ============================================================
.section .data

archivo_csv:    .asciz "lecturas.csv"
archivo_salida: .asciz "resultado_media.txt"

// Cada etiqueta _len calcula automaticamente la longitud
lbl_module:     .ascii "MODULE=WEIGHTED_MEAN\n"
    .equ lbl_module_len, . - lbl_module

lbl_total:      .ascii "TOTAL_VALUES=30\n"
    .equ lbl_total_len, . - lbl_total

lbl_sumx:       .ascii "SUM_X="
    .equ lbl_sumx_len, . - lbl_sumx

lbl_wsum:       .ascii "WEIGHT_SUM="
    .equ lbl_wsum_len, . - lbl_wsum

lbl_mean:       .ascii "WEIGHTED_MEAN="
    .equ lbl_mean_len, . - lbl_mean


// ============================================================
// SECCION BSS - memoria sin inicializar
// ============================================================
.section .bss

buf_csv:    .skip 4096      // buffer para leer todo el CSV de una vez
buf_num:    .skip 32        // buffer temporal para convertir numero a texto
datos:      .skip 240       // arreglo de 30 valores (30 x 8 bytes)

// Resultados del calculo
sum_x:      .skip 8         // suma simple de los datos
wpond:      .skip 8         // suma ponderada S(Xi * Wi)
wsum:       .skip 8         // suma de pesos S(Wi) = 465
media:      .skip 8         // media ponderada final


// ============================================================
// SECCION DE CODIGO
// ============================================================
.section .text
.global _start
.extern int_a_ascii         // viene de utils.s (no se usa directamente aqui)


// ============================================================
// _start : punto de entrada del programa
// Flujo: leer CSV -> parsear -> calcular -> escribir resultado
// ============================================================
_start:
    // 1. Abrir lecturas.csv
    mov  x8,  SYS_OPENAT
    mov  x0,  AT_FDCWD
    adr  x1,  archivo_csv
    mov  x2,  O_RDONLY
    mov  x3,  0
    svc  0
    cmp  x0,  0
    blt  salir_error        // si fd < 0, no se pudo abrir
    mov  x19, x0            // x19 = descriptor del CSV

    // 2. Leer todo el archivo en buf_csv
    mov  x8,  SYS_READ
    mov  x0,  x19
    adr  x1,  buf_csv
    mov  x2,  4096
    svc  0                  // x0 = bytes leidos (lo usamos en parsear)
    mov  x20, x0            // x20 = bytes leidos

    // 3. Cerrar el archivo (ya tenemos los datos en memoria)
    mov  x8,  SYS_CLOSE
    mov  x0,  x19
    svc  0

    // 4. Parsear el CSV y llenar el arreglo datos[]
    bl   parsear_csv

    // 5. Calcular la media ponderada
    bl   calcular_media

    // 6. Escribir resultado_media.txt
    bl   escribir_resultado

    // 7. Salir con exito
    mov  x8,  SYS_EXIT
    mov  x0,  0
    svc  0

salir_error:
    mov  x8,  SYS_EXIT
    mov  x0,  1
    svc  0


// ============================================================
// parsear_csv
//
// Recorre buf_csv y extrae la columna COL_TEMP de cada fila.
// Guarda los 30 enteros en datos[].
//
// Registros usados:
//   x19 = puntero actual en el buffer
//   x20 = puntero al final del buffer (base + bytes leidos)
//   x21 = indice de fila actual (0..29)
//   x22 = columna actual dentro de la fila
//   x23 = valor numerico acumulado del campo actual
// ============================================================
parsear_csv:
    stp  x29, x30, [sp, #-64]!
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    mov  x29, sp

    adr  x19, buf_csv
    add  x20, x19, x20      // fin del buffer = inicio + bytes leidos
    adr  x24, datos
    mov  x21, 0             // fila = 0

    // Saltar la cabecera (primera linea con los nombres de columnas)
saltar_cabecera:
    cmp  x19, x20
    bge  parsear_fin
    ldrb w0,  [x19], #1
    cmp  w0,  '\n'
    bne  saltar_cabecera

    // --- Leer cada fila de datos ---
siguiente_fila:
    cmp  x21, N             // si ya tenemos 30 filas, terminamos
    bge  parsear_fin
    cmp  x19, x20           // si llegamos al fin del buffer, terminamos
    bge  parsear_fin

    ldrb w0,  [x19]         // checar si es el marcador de fin '$'
    cmp  w0,  '$'
    beq  parsear_fin

    mov  x22, 0             // columna actual = 0
    mov  x23, 0             // valor acumulado = 0

    // --- Leer caracter por caracter dentro de la fila ---
siguiente_char:
    cmp  x19, x20
    bge  parsear_fin

    ldrb w0,  [x19], #1

    cmp  w0,  '\r'          // ignorar retorno de carro (archivos Windows)
    beq  siguiente_char

    cmp  w0,  '\n'          // fin de linea: guardar si estabamos en COL_TEMP
    beq  fin_de_linea

    cmp  w0,  ','           // coma: separador de columna
    beq  en_coma

    // Si es un digito, acumularlo en x23
    cmp  w0,  '0'
    blt  siguiente_char
    cmp  w0,  '9'
    bgt  siguiente_char
    mov  x9,  10
    mul  x23, x23, x9
    sub  w0,  w0, '0'
    add  x23, x23, x0
    b    siguiente_char

en_coma:
    // Si esta coma cierra la columna que buscamos, guardamos el valor
    cmp  x22, COL_TEMP
    beq  guardar_valor
    add  x22, x22, 1        // avanzar a la siguiente columna
    mov  x23, 0             // resetear acumulador
    b    siguiente_char

fin_de_linea:
    // Si la columna objetivo es la ultima y llego el \n
    cmp  x22, COL_TEMP
    beq  guardar_valor
    add  x21, x21, 1        // fila sin el dato buscado, igual contamos
    b    siguiente_fila

guardar_valor:
    str  x23, [x24, x21, lsl #3]    // datos[x21] = x23
    add  x21, x21, 1

    // Saltar el resto de la fila hasta el siguiente \n
saltar_resto:
    cmp  x19, x20
    bge  parsear_fin
    ldrb w0,  [x19], #1
    cmp  w0,  '\n'
    bne  saltar_resto
    b    siguiente_fila

parsear_fin:
    ldp  x23, x24, [sp, #48]
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #64
    ret


// ============================================================
// calcular_media
//
// Recorre datos[0..29] y calcula:
//   sum_x = S(Xi)           suma simple de los datos
//   wpond = S(Xi * Wi)      suma ponderada, Wi = i+1
//   wsum  = S(Wi)           suma de pesos = 465
//   media = wpond / wsum
//
// Registros usados:
//   x19 = indice i (0..29)
//   x20 = peso Wi (1..30)
//   x21 = acumulador sum_x
//   x22 = acumulador wpond
//   x23 = acumulador wsum
//   x24 = base del arreglo datos
//   x25 = dato actual datos[i]
// ============================================================
calcular_media:
    stp  x29, x30, [sp, #-64]!
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    stp  x23, x24, [sp, #48]
    mov  x29, sp

    adr  x24, datos
    mov  x19, 0             // indice i = 0
    mov  x20, 1             // peso W1 = 1
    mov  x21, 0             // sum_x = 0
    mov  x22, 0             // wpond = 0
    mov  x23, 0             // wsum  = 0

bucle_calcular:
    cmp  x19, N
    bge  guardar_resultados

    ldr  x25, [x24, x19, lsl #3]    // x25 = datos[i]

    add  x21, x21, x25              // sum_x += datos[i]

    mul  x9,  x25, x20
    add  x22, x22, x9               // wpond += datos[i] * Wi

    add  x23, x23, x20              // wsum  += Wi

    add  x19, x19, 1                // i++
    add  x20, x20, 1                // Wi++
    b    bucle_calcular

guardar_resultados:
    udiv x25, x22, x23              // media = wpond / wsum

    adr  x9, sum_x
    str  x21, [x9]
    adr  x9, wpond
    str  x22, [x9]
    adr  x9, wsum
    str  x23, [x9]
    adr  x9, media
    str  x25, [x9]

    ldp  x23, x24, [sp, #48]
    ldp  x21, x22, [sp, #32]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #64
    ret


// ============================================================
// escribir_resultado
//
// Crea resultado_media.txt y escribe las 5 lineas del formato:
//   MODULE=WEIGHTED_MEAN
//   TOTAL_VALUES=30
//   SUM_X=<valor>
//   WEIGHT_SUM=<valor>
//   WEIGHTED_MEAN=<valor>
//
// Registros usados:
//   x19 = descriptor del archivo de salida (fd)
// ============================================================
escribir_resultado:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    // Crear/abrir resultado_media.txt
    mov  x8,  SYS_OPENAT
    mov  x0,  AT_FDCWD
    adr  x1,  archivo_salida
    mov  x2,  O_WRONLY | O_CREAT | O_TRUNC
    mov  x3,  PERM_644
    svc  0
    cmp  x0,  0
    blt  escribir_fin
    mov  x19, x0            // x19 = fd del archivo de salida

    // Linea 1: MODULE=WEIGHTED_MEAN
    adr  x0, lbl_module
    mov  x1, lbl_module_len
    bl   escribir_buf

    // Linea 2: TOTAL_VALUES=30
    adr  x0, lbl_total
    mov  x1, lbl_total_len
    bl   escribir_buf

    // Linea 3: SUM_X=<valor>
    adr  x0, lbl_sumx
    mov  x1, lbl_sumx_len
    bl   escribir_buf
    adr  x9, sum_x
    ldr  x0, [x9]
    bl   escribir_numero

    // Linea 4: WEIGHT_SUM=<valor>
    adr  x0, lbl_wsum
    mov  x1, lbl_wsum_len
    bl   escribir_buf
    adr  x9, wsum
    ldr  x0, [x9]
    bl   escribir_numero

    // Linea 5: WEIGHTED_MEAN=<valor>
    adr  x0, lbl_mean
    mov  x1, lbl_mean_len
    bl   escribir_buf
    adr  x9, media
    ldr  x0, [x9]
    bl   escribir_numero

    // Cerrar archivo
    mov  x8, SYS_CLOSE
    mov  x0, x19
    svc  0

escribir_fin:
    ldp  x29, x30, [sp], #16
    ret


// ============================================================
// escribir_buf
// Escribe x1 bytes desde la direccion x0 al archivo x19.
// ============================================================
escribir_buf:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    mov  x8,  SYS_WRITE
    mov  x2,  x1            // tamanio
    mov  x1,  x0            // puntero
    mov  x0,  x19           // fd
    svc  0

    ldp  x29, x30, [sp], #16
    ret


// ============================================================
// escribir_numero
// Convierte el entero en x0 a texto ASCII y lo escribe
// en el archivo x19, seguido de un salto de linea '\n'.
//
// Estrategia: construir los digitos de derecha a izquierda
// en buf_num usando division por 10, luego escribir.
// ============================================================
escribir_numero:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    adr  x9,  buf_num
    add  x10, x9, #28       // x10 apunta al ultimo byte del buffer

    // Poner '\n' en la posicion 28
    mov  w11, '\n'
    strb w11, [x10]

    // Caso especial: si el numero es 0
    cbnz x0, extraer_digitos
    mov  w11, '0'
    sub  x10, x10, #1
    strb w11, [x10]
    b    imprimir_numero

    // Extraer digitos de derecha a izquierda
extraer_digitos:
    cbz  x0, imprimir_numero
    mov  x11, 10
    udiv x12, x0, x11       // x12 = x0 / 10
    msub x12, x12, x11, x0  // x12 = x0 % 10  (resto)
    add  w12, w12, '0'      // convertir a ASCII
    sub  x10, x10, #1
    strb w12, [x10]
    udiv x0,  x0, x11       // x0 = x0 / 10 (siguiente digito)
    b    extraer_digitos

imprimir_numero:
    // Calcular cuantos bytes escribir: desde x10 hasta posicion 28 + el \n
    adr  x9, buf_num
    add  x9, x9, #28
    sub  x1, x9, x10
    add  x1, x1, #1         // incluir el '\n'
    mov  x0, x10
    bl   escribir_buf

    ldp  x29, x30, [sp], #16
    ret

// ---- Fin modulo_1_media.s ---------------------------------
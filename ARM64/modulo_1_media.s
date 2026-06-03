// ============================================================
// modulo_1_media.s - Media Aritmética Ponderada
// Proyecto: Invernadero Inteligente IoT
// Integrante 1
// ============================================================
// Calcula la media ponderada de 30 datos de temperatura
// usando pesos crecientes del 1 al 30.
//
// Fórmula: MEDIA_PONDERADA = Σ(X_i * W_i) / ΣW_i
//   Donde W_i = peso de cada lectura (1, 2, 3, ... 30)
//
// Entrada:  lecturas.csv  (columna TEMP = columna 1)
// Salida:   resultado_media.txt
// ============================================================

.section .data

// Nombre del archivo de salida
nombre_salida:
    .asciz "resultado_media.txt"

// Etiquetas para el archivo de salida (formato exacto del proyecto)
lbl_module:
    .asciz "MODULE=WEIGHTED_MEAN\n"
lbl_module_len = . - lbl_module

lbl_total:
    .asciz "TOTAL_VALUES=30\n"
lbl_total_len = . - lbl_total

lbl_sumx:
    .asciz "SUM_X="
lbl_sumx_len = . - lbl_sumx

lbl_wsum:
    .asciz "WEIGHT_SUM="
lbl_wsum_len = . - lbl_wsum

lbl_mean:
    .asciz "WEIGHTED_MEAN="
lbl_mean_len = . - lbl_mean

newline:
    .asciz "\n"
newline_len = . - newline

// Buffer para construir el archivo de salida
.comm resultado_buf, 512, 8

// Buffer para números en texto
.comm num_buf, 32, 8

// Variables para los cálculos
.comm suma_x,         8, 8    // Σ X_i (suma simple de datos)
.comm suma_ponderada, 8, 8    // Σ(X_i * W_i)
.comm suma_pesos,     8, 8    // Σ W_i
.comm media_pond,     8, 8    // resultado final

// ============================================================
.section .text
.global _start

// Importar funciones de utils.s
.extern leer_datos
.extern int_a_ascii
.extern ascii_a_int
.extern escribir_archivo

// ============================================================
// PUNTO DE ENTRADA PRINCIPAL
// ============================================================
_start:

    // --------------------------------------------------------
    // PASO 1: Leer columna de temperatura (columna 1 = TEMP)
    // --------------------------------------------------------
    mov x0, #1              // columna 1 = TEMP en el CSV
    bl leer_datos           // los 30 datos quedan en 'datos'
    // x0 ahora tiene cuántos datos se leyeron

    // --------------------------------------------------------
    // PASO 2: Calcular Σ X_i, Σ(X_i * W_i) y Σ W_i
    // --------------------------------------------------------
    // Inicializar acumuladores en cero
    adr x1, suma_x
    str xzr, [x1]
    adr x1, suma_ponderada
    str xzr, [x1]
    adr x1, suma_pesos
    str xzr, [x1]

    // Cargar dirección del arreglo de datos
    adr x9, datos           // x9 = puntero al arreglo datos[]
    mov x10, #0             // x10 = índice i (0 a 29)
    mov x11, #1             // x11 = peso W_i (empieza en 1)

.loop_calcular:
    // ¿Ya procesamos 30 datos?
    cmp x10, #30
    bge .calculos_listos

    // Cargar datos[i]
    ldr x12, [x9, x10, lsl #3]   // x12 = X_i

    // Acumular suma simple: suma_x += X_i
    adr x13, suma_x
    ldr x14, [x13]
    add x14, x14, x12
    str x14, [x13]

    // Acumular suma ponderada: suma_ponderada += X_i * W_i
    mul x15, x12, x11             // x15 = X_i * W_i
    adr x13, suma_ponderada
    ldr x14, [x13]
    add x14, x14, x15
    str x14, [x13]

    // Acumular suma de pesos: suma_pesos += W_i
    adr x13, suma_pesos
    ldr x14, [x13]
    add x14, x14, x11
    str x14, [x13]

    // Incrementar índice y peso
    add x10, x10, #1        // i++
    add x11, x11, #1        // W_i++ (pesos: 1, 2, 3, ..., 30)

    b .loop_calcular

.calculos_listos:

    // --------------------------------------------------------
    // PASO 3: Calcular media ponderada
    // MEDIA_PONDERADA = suma_ponderada / suma_pesos
    // --------------------------------------------------------
    adr x0, suma_ponderada
    ldr x0, [x0]            // x0 = Σ(X_i * W_i)
    adr x1, suma_pesos
    ldr x1, [x1]            // x1 = Σ W_i

    // División entera: media = suma_ponderada / suma_pesos
    udiv x2, x0, x1         // x2 = media ponderada

    // Guardar resultado
    adr x3, media_pond
    str x2, [x3]

    // --------------------------------------------------------
    // PASO 4: Construir el archivo de salida resultado_media.txt
    // --------------------------------------------------------
    // Usamos write() directo para cada línea
    // Abrir archivo de salida
    mov x8, #56             // openat
    mov x0, #-100           // AT_FDCWD
    adr x1, nombre_salida
    mov x2, #577            // O_WRONLY | O_CREAT | O_TRUNC
    mov x3, #0644
    svc #0
    mov x19, x0             // x19 = descriptor del archivo salida

    // --- Escribir: MODULE=WEIGHTED_MEAN\n ---
    bl .escribir_module

    // --- Escribir: TOTAL_VALUES=30\n ---
    bl .escribir_total

    // --- Escribir: SUM_X=<valor>\n ---
    bl .escribir_sumx

    // --- Escribir: WEIGHT_SUM=<valor>\n ---
    bl .escribir_wsum

    // --- Escribir: WEIGHTED_MEAN=<valor>\n ---
    bl .escribir_mean

    // Cerrar archivo de salida
    mov x8, #57             // close
    mov x0, x19
    svc #0

    // --------------------------------------------------------
    // PASO 5: También mostrar en pantalla (stdout)
    // --------------------------------------------------------
    bl .imprimir_pantalla

    // --------------------------------------------------------
    // PASO 6: Salir del programa
    // --------------------------------------------------------
    mov x8, #93             // syscall exit
    mov x0, #0              // código de salida 0 = éxito
    svc #0


// ============================================================
// SUBRUTINA: escribir línea "MODULE=WEIGHTED_MEAN\n"
// ============================================================
.escribir_module:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    mov x8, #64             // write
    mov x0, x19             // descriptor archivo salida
    adr x1, lbl_module
    mov x2, #21             // longitud de "MODULE=WEIGHTED_MEAN\n"
    svc #0

    ldp x29, x30, [sp], #16
    ret

// ============================================================
// SUBRUTINA: escribir línea "TOTAL_VALUES=30\n"
// ============================================================
.escribir_total:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    mov x8, #64
    mov x0, x19
    adr x1, lbl_total
    mov x2, #16
    svc #0

    ldp x29, x30, [sp], #16
    ret

// ============================================================
// SUBRUTINA: escribir línea "SUM_X=<valor>\n"
// ============================================================
.escribir_sumx:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // Escribir etiqueta "SUM_X="
    mov x8, #64
    mov x0, x19
    adr x1, lbl_sumx
    mov x2, #6
    svc #0

    // Convertir suma_x a texto y escribir
    adr x0, suma_x
    ldr x0, [x0]
    adr x1, num_buf
    bl int_a_ascii

    // Escribir el número
    mov x8, #64
    mov x0, x19
    adr x1, num_buf
    bl .strlen_num
    svc #0

    // Escribir "\n"
    mov x8, #64
    mov x0, x19
    adr x1, newline
    mov x2, #1
    svc #0

    ldp x29, x30, [sp], #16
    ret

// ============================================================
// SUBRUTINA: escribir línea "WEIGHT_SUM=<valor>\n"
// ============================================================
.escribir_wsum:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // Escribir etiqueta "WEIGHT_SUM="
    mov x8, #64
    mov x0, x19
    adr x1, lbl_wsum
    mov x2, #11
    svc #0

    // Convertir suma_pesos a texto
    adr x0, suma_pesos
    ldr x0, [x0]
    adr x1, num_buf
    bl int_a_ascii

    // Escribir el número
    mov x8, #64
    mov x0, x19
    adr x1, num_buf
    bl .strlen_num
    svc #0

    // Escribir "\n"
    mov x8, #64
    mov x0, x19
    adr x1, newline
    mov x2, #1
    svc #0

    ldp x29, x30, [sp], #16
    ret

// ============================================================
// SUBRUTINA: escribir línea "WEIGHTED_MEAN=<valor>\n"
// ============================================================
.escribir_mean:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // Escribir etiqueta "WEIGHTED_MEAN="
    mov x8, #64
    mov x0, x19
    adr x1, lbl_mean
    mov x2, #14
    svc #0

    // Convertir media_pond a texto
    adr x0, media_pond
    ldr x0, [x0]
    adr x1, num_buf
    bl int_a_ascii

    // Escribir el número
    mov x8, #64
    mov x0, x19
    adr x1, num_buf
    bl .strlen_num
    svc #0

    // Escribir "\n"
    mov x8, #64
    mov x0, x19
    adr x1, newline
    mov x2, #1
    svc #0

    ldp x29, x30, [sp], #16
    ret

// ============================================================
// SUBRUTINA: imprimir resultados en pantalla (stdout)
// ============================================================
.imprimir_pantalla:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // Reusar las mismas subrutinas pero con stdout (fd=1)
    // Guardamos x19 (fd salida) y lo reemplazamos con 1
    mov x20, x19
    mov x19, #1             // stdout

    bl .escribir_module
    bl .escribir_total
    bl .escribir_sumx
    bl .escribir_wsum
    bl .escribir_mean

    mov x19, x20            // restaurar fd original

    ldp x29, x30, [sp], #16
    ret

// ============================================================
// SUBRUTINA INTERNA: calcular longitud de num_buf
// Retorna x2 = longitud del string en num_buf
// ============================================================
.strlen_num:
    adr x1, num_buf
    mov x2, #0
.loop_len:
    ldrb w3, [x1, x2]
    cmp w3, #0
    beq .fin_len
    add x2, x2, #1
    b .loop_len
.fin_len:
    ret
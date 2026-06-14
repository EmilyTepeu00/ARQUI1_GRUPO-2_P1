/* ====================================================================================
                            Módulo 4: Predicción de Próximo Valor
   ====================================================================================
    modulo_4_prediccion.s
    Módulo 4: Predicción de Próximo Valor
    Proyecto: Invernadero Inteligente IoT - ACYE1
    Responsable: Diana Myriam Priscila Santizo Cáceres

    Variable analizada : LUZ (columna 5 del CSV)
    Entrada            : lecturas.csv
    Salida             : resultado_prediccion.txt

    ¿Qué hace este módulo?
    1. Lee 30 datos de intensidad lumínica desde el archivo lecturas.csv
    2. Calcula el próximo valor usando un modelo de predicción simple
       basado en la tendencia de los últimos valores.
    3. Escribe el resultado en resultado_prediccion.txt
 
  Modelo de Predicción:
    - Se calcula la diferencia entre cada par de valores consecutivos.
    - Se promedia esta diferencia para obtener una tendencia.
    - El próximo valor se predice sumando esta tendencia al último valor.

    Cálculos realizados:
    1. Valor inicial (Fila 1)
    2. Valor final (Fila 30)
    3. Diferencia total = Final - Inicial
    4. Promedio de cambio = Diferencia / 29
    5. Predicción = Final + Promedio_cambio

   ====================================================================================
*/

.extern leer_datos
.extern datos
.extern int_a_ascii

// syscalls que necesito para abrir, escribir y cerrar el archivo
.equ SYS_OPENAT,  56
.equ SYS_CLOSE,   57
.equ SYS_WRITE,   64
.equ SYS_EXIT,    93
.equ AT_FDCWD,   -100
.equ O_WRONLY,    1
.equ O_CREAT,     64
.equ O_TRUNC,     512
.equ PERM_644,    0644

.section .data

nombre_salida:  .asciz "resultado_prediccion.txt"

// textos fijos que van en el archivo de salida
lbl_header: .asciz "MODULE=PREDICTION\nINITIAL_VALUE="
lbl_final:  .asciz "\nFINAL_VALUE="
lbl_diff:   .asciz "\nTOTAL_DIFF="
lbl_avg:    .asciz "\nAVG_CHANGE="
lbl_next:   .asciz "\nNEXT_VALUE="
lbl_nl:     .asciz "\n"

.section .bss

// aqui armo todo el texto antes de escribirlo al archivo
buffer_salida:  .skip 512
buf_conv:       .skip 32

.section .text
.global _start

_start:
    // leo la columna 5 (LUZ) del CSV, utils llena datos[] con los 30 valores
    mov x0, #5
    bl  leer_datos

    // guardo el valor inicial (datos[0]) y el valor final (datos[29])
    // uso registros x19 en adelante porque no se pierden con bl
    adr x9,  datos
    ldr x19, [x9, #0]       // x19 = valor inicial = datos[0]
    ldr x22, [x9, #232]     // x22 = valor final   = datos[29] -> 29*8 = 232

    // hago los calculos
    sub x23, x22, x19       // x23 = diferencia total = final - inicial
    mov x4,  #29            // 29 intervalos entre 30 datos
    sdiv x24, x23, x4       // x24 = promedio de cambio = diferencia / 29
    add  x25, x22, x24      // x25 = prediccion = final + promedio de cambio

    // empiezo a armar el texto en buffer_salida
    // x20 es el puntero de escritura, va avanzando con cada cosa que agrego
    adr x20, buffer_salida

    // escribo MODULE=PREDICTION y INITIAL_VALUE=valor
    adr x0, lbl_header
    bl  copiar_a_buffer
    mov x0, x19
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // escribo FINAL_VALUE=valor
    adr x0, lbl_final
    bl  copiar_a_buffer
    mov x0, x22
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // escribo TOTAL_DIFF=valor
    adr x0, lbl_diff
    bl  copiar_a_buffer
    mov x0, x23
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // escribo AVG_CHANGE=valor
    adr x0, lbl_avg
    bl  copiar_a_buffer
    mov x0, x24
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // escribo NEXT_VALUE=valor
    adr x0, lbl_next
    bl  copiar_a_buffer
    mov x0, x25
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // salto de linea al final
    adr x0, lbl_nl
    bl  copiar_a_buffer

    // calculo cuantos bytes escribi en el buffer
    // x20 ya avanzo hasta el final, x1 apunta al inicio
    adr x1, buffer_salida
    sub x26, x20, x1        // x26 = cantidad de bytes del buffer

    // creo o sobreescribo resultado_prediccion.txt
    mov x8, #56
    mov x0, #-100
    adr x1, nombre_salida
    mov x2, #577            // crear si no existe, borrar contenido anterior
    mov x3, #0644
    svc #0
    mov x10, x0             // guardo el descriptor del archivo

    // escribo el buffer al archivo
    mov x8, #64
    mov x0, x10
    adr x1, buffer_salida
    mov x2, x26
    svc #0

    // cierro el archivo
    mov x8, #57
    mov x0, x10
    svc #0

    // tambien muestro el resultado en la terminal
    mov x8, #64
    mov x0, #1              // 1 = stdout = pantalla
    adr x1, buffer_salida
    mov x2, x26
    svc #0

    // fin del programa
    mov x8, #93
    mov x0, #0
    svc #0


// ============================================================
// copiar_a_buffer
// Copia una cadena terminada en \0 desde x0 hacia x20
// x20 avanza automaticamente con cada caracter que copia
// ============================================================
copiar_a_buffer:
    ldrb w21, [x0], #1      // leo un byte y avanzo x0
    cbz  w21, fin_copiar    // si es \0 termino
    strb w21, [x20], #1     // guardo el byte y avanzo x20
    b    copiar_a_buffer
fin_copiar:
    ret


// ============================================================
// formatear_numero
// Si el numero en x0 es negativo pone el signo '-' primero
// y luego llama a int_a_ascii de utils para convertir el resto
// x1 = buffer destino para el texto
// ============================================================
formatear_numero:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    cmp  x0, #0
    bge  conv_positivo      // si es positivo o cero salto directo

    // si es negativo pongo el '-' antes del numero
    mov  w9, #45            // 45 es el codigo ASCII del '-'
    strb w9, [x1], #1       // guardo el '-' y avanzo el puntero
    neg  x0, x0             // convierto a positivo para int_a_ascii

conv_positivo:
    bl   int_a_ascii        // int_a_ascii convierte x0 al texto en x1
    ldp  x29, x30, [sp], #16
    ret
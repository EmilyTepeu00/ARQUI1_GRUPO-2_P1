/* ====================================================================================
                        Modulo 4: Prediccion de Proximo Valor
   ====================================================================================
    modulo_4_prediccion.s
    Responsable: Diana Myriam Priscila Santizo Caceres

    Lee la columna que el usuario seleccione desde el dashboard.
    El numero de columna llega como argv[1] cuando Python ejecuta
    el binario. Si no viene argumento, usa columna 2 (TEMP).

    Calculos:
    1. Valor inicial (datos[0])
    2. Valor final   (datos[29])
    3. Diferencia total = Final - Inicial
    4. Promedio de cambio = Diferencia / 29
    5. Prediccion = Final + Promedio_cambio

    Archivo de entrada: lecturas.csv
    Archivo de salida:  resultado_prediccion.txt
   ====================================================================================
*/

.extern leer_datos
.extern datos
.extern int_a_ascii
.extern ascii_a_int

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

// textos fijos del archivo de salida
// los \n estan dentro del string para que queden bien formateados
lbl_header: .asciz "MODULE=PREDICTION\nINITIAL_VALUE="
lbl_final:  .asciz "\nFINAL_VALUE="
lbl_diff:   .asciz "\nTOTAL_DIFF="
lbl_avg:    .asciz "\nAVG_CHANGE="
lbl_next:   .asciz "\nNEXT_VALUE="
lbl_nl:     .asciz "\n"

.section .bss

buffer_salida:  .skip 512
buf_conv:       .skip 32

.section .text
.global _start

_start:
    // --------------------------------------------------------
    // LECTURA DE argv[1]: el numero de columna que manda Python
    // [sp]    = argc
    // [sp+16] = puntero al string de argv[1] (ej: "2" para TEMP)
    // Si no viene argumento usamos columna 2 (TEMP) por defecto
    // --------------------------------------------------------
    ldr x0, [sp]            // x0 = argc
    cmp x0, #2              // hay al menos 1 argumento?
    blt .usar_default_4     // no -> default

    ldr x0, [sp, #16]       // x0 = puntero a argv[1]
    bl  ascii_a_int          // convierte string a entero en x0
    b   .llamar_leer_4

.usar_default_4:
    mov x0, #2              // default: columna 2 = TEMP

.llamar_leer_4:
    // leer_datos llena datos[] con los 30 valores de la columna x0
    bl  leer_datos

    // --------------------------------------------------------
    // CALCULOS de prediccion lineal simple
    // x19 = valor inicial (datos[0])
    // x22 = valor final   (datos[29])
    // x23 = diferencia total
    // x24 = promedio de cambio (puede ser negativo)
    // x25 = prediccion = final + promedio
    // --------------------------------------------------------
    adr x9,  datos
    ldr x19, [x9, #0]       // datos[0] = primer valor
    ldr x22, [x9, #232]     // datos[29] = ultimo valor (29 * 8 = 232)

    sub x23, x22, x19       // diferencia total = final - inicial
    mov x4,  #29            // 29 intervalos entre 30 datos
    sdiv x24, x23, x4       // promedio de cambio = diferencia / 29
    add  x25, x22, x24      // prediccion = final + promedio

    // --------------------------------------------------------
    // ARMAR EL TEXTO en buffer_salida
    // x20 es el puntero de escritura que avanza con cada caracter
    // --------------------------------------------------------
    adr x20, buffer_salida

    // MODULE=PREDICTION\nINITIAL_VALUE=valor
    adr x0, lbl_header
    bl  copiar_a_buffer
    mov x0, x19
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // \nFINAL_VALUE=valor
    adr x0, lbl_final
    bl  copiar_a_buffer
    mov x0, x22
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // \nTOTAL_DIFF=valor
    adr x0, lbl_diff
    bl  copiar_a_buffer
    mov x0, x23
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // \nAVG_CHANGE=valor
    adr x0, lbl_avg
    bl  copiar_a_buffer
    mov x0, x24
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // \nNEXT_VALUE=valor
    adr x0, lbl_next
    bl  copiar_a_buffer
    mov x0, x25
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // salto de linea final
    adr x0, lbl_nl
    bl  copiar_a_buffer

    // calcular cuantos bytes escribimos en el buffer
    adr x1, buffer_salida
    sub x26, x20, x1        // x26 = longitud total del texto

    // --------------------------------------------------------
    // ESCRIBIR AL ARCHIVO resultado_prediccion.txt
    // --------------------------------------------------------
    mov x8, #56
    mov x0, #-100
    adr x1, nombre_salida
    mov x2, #577
    mov x3, #0644
    svc #0
    mov x10, x0             // x10 = descriptor del archivo

    mov x8, #64
    mov x0, x10
    adr x1, buffer_salida
    mov x2, x26
    svc #0

    mov x8, #57
    mov x0, x10
    svc #0

    // MOSTRAR EN TERMINAL
    mov x8, #64
    mov x0, #1
    adr x1, buffer_salida
    mov x2, x26
    svc #0

    mov x8, #93
    mov x0, #0
    svc #0


// ============================================================
// copiar_a_buffer
// Copia una cadena terminada en \0 desde x0 hacia x20
// x20 avanza automaticamente con cada caracter copiado
// ============================================================
copiar_a_buffer:
    ldrb w21, [x0], #1      // leer byte y avanzar x0
    cbz  w21, fin_copiar    // si es \0 terminamos
    strb w21, [x20], #1     // guardar byte y avanzar x20
    b    copiar_a_buffer
fin_copiar:
    ret


// ============================================================
// formatear_numero
// Si x0 es negativo, escribe '-' primero y luego el valor absoluto
// Llama a int_a_ascii de utils para la conversion
// x1 = buffer destino del texto convertido
// ============================================================
formatear_numero:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    cmp  x0, #0
    bge  conv_positivo      // si es >= 0 no necesitamos el signo

    // numero negativo: poner el '-' antes
    mov  w9, #45            // ASCII '-'
    strb w9, [x1], #1       // guardar '-' y avanzar x1
    neg  x0, x0             // convertir a positivo para int_a_ascii

conv_positivo:
    bl   int_a_ascii        // convierte x0 al texto en x1
    ldp  x29, x30, [sp], #16
    ret

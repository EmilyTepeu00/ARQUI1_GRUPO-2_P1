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

.section .data
nombre_salida:  .asciz "resultado_prediccion.txt"

// Textos fijos en formato .asciz 
lbl_header: .asciz "MODULE=PREDICTION\nINITIAL_VALUE="
lbl_final:  .asciz "\nFINAL_VALUE="
lbl_diff:   .asciz "\nTOTAL_DIFF="
lbl_avg:    .asciz "\nAVG_CHANGE="
lbl_next:   .asciz "\nNEXT_VALUE="
lbl_nl:     .asciz "\n"

.section .bss
buffer_salida:  .skip 512    // Buffer donde se armara el archivo completo
buf_conv:       .skip 32     // Buffer temporal para conversiones numéricas

.section .text
.global _start

// Funciones y arreglos importados desde utils.s
.extern leer_datos
.extern datos
.extern int_a_ascii
.extern escribir_archivo

_start:
    // 1. Leer los datos de la columna LUZ (índice 5 de base 0)
    mov x0, #5
    bl  leer_datos          // El arreglo global 'datos' se llena con 30 registros

    // 2. Extraer el valor inicial (fila 1) y valor final (fila 30)
    // PASAMOS A REGISTROS SEGUROS (x19, x22-x25) QUE NO SE CORRUMPEN CON 'bl'
    adr x9, datos           // Cargar la dirección base del arreglo 'datos'
    ldr x19, [x9, #0]       // x19 = Valor Inicial (datos[0])
    ldr x22, [x9, #232]   // x22 = Valor Final (datos[29] -> 29 * 8 bytes = 232)

    // 3. Realizar los cálculos matemáticos
    sub x23, x22, x19       // x23 = Diferencia total (Final - Inicial)
    mov x4, #29             // x4 = 29 intervalos de cambio (30 datos - 1)
    sdiv x24, x23, x4       // x24 = Promedio de cambio (Diferencia / 29)
    add  x25, x22, x24      // x25 = Predicción (Final + Promedio de cambio)

    // 4. Construcción del Buffer de salida en memoria
    adr x20, buffer_salida  // x20 será el puntero de escritura en el buffer

    // --- Escribir Encabezado y Valor Inicial ---
    adr x0, lbl_header
    bl  copiar_a_buffer
    mov x0, x19             
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // --- Escribir Valor Final ---
    adr x0, lbl_final
    bl  copiar_a_buffer
    mov x0, x22             
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // --- Escribir Diferencia Total ---
    adr x0, lbl_diff
    bl  copiar_a_buffer
    mov x0, x23            
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // --- Escribir Promedio de Cambio ---
    adr x0, lbl_avg
    bl  copiar_a_buffer
    mov x0, x24            
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // --- Escribir Predicción (Siguiente Valor) ---
    adr x0, lbl_next
    bl  copiar_a_buffer
    mov x0, x25             
    adr x1, buf_conv
    bl  formatear_numero
    adr x0, buf_conv
    bl  copiar_a_buffer

    // --- Escribir salto de línea final ---
    adr x0, lbl_nl
    bl  copiar_a_buffer

    // 5. Guardar el buffer completo en el archivo físico
    adr x0, nombre_salida
    adr x1, buffer_salida
    sub x2, x20, x1         
    bl  escribir_archivo

exit_program:
    // Terminar la ejecución del programa de forma limpia
    mov x0, #0
    mov x8, #93             // Syscall SYS_EXIT
    svc #0


// ============================================================
// FUNCIONES AUXILIARES INTERNAS
// ============================================================

// --- Función: copiar_a_buffer ---
// Copia una cadena terminada en \0 (x0) hacia el buffer de salida (x20)
copiar_a_buffer:
    ldrb w21, [x0], #1
    cbz  w21, fin_copiar
    strb w21, [x20], #1
    b    copiar_a_buffer
fin_copiar:
    ret

// --- Función: formatear_numero ---
// Revisa si el número es negativo. Si lo es, añade el '-' al buffer destino 
// y luego llama al conversor normal de utils.s
formatear_numero:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp

    cmp  x0, #0
    bge  conv_positivo      // Si es mayor o igual a 0, saltar

    // Si es negativo: colocar '-' en el buffer de conversión
    mov  w9, #45            // Código ASCII para '-'
    strb w9, [x1], #1       // Guardar el '-' y avanzar el puntero del buffer
    neg  x0, x0             // Volver el número positivo para int_a_ascii

conv_positivo:
    bl   int_a_ascii        // Llamar a la función del archivo utils.s
    ldp  x29, x30, [sp], #16
    ret

/*  Ejecutar para pruebas:
    make modulo_4_prediccion
    qemu-aarch64 ./modulo_4_prediccion
    cat resultado_prediccion.txt
*/

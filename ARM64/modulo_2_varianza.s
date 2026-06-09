// ============================================================
// modulo_2_varianza.s
// Módulo 2: Varianza y Desviación Estándar
// Responsable: Integrante 2
// 
// ¿Qué hace este módulo?
//   1. Lee 30 datos de Humedad del Aire desde lecturas.csv
//   2. Calcula la media (promedio)
//   3. Calcula la varianza
//   4. Calcula la desviación estándar (raíz de la varianza)
//   5. Escribe los resultados en resultado_varianza.txt
//
// Fórmulas:
//   MEDIA = ΣX / N
//   VAR   = Σ(X - MEDIA)² / N
//   DESV  = √VAR
//
// Donde N = 30
// ============================================================

// Usamos funciones de utils.s:
.extern leer_datos       // lee el CSV y llena el arreglo 'datos'
.extern int_a_ascii      // convierte número a texto
.extern ascii_a_int      // convierte texto a número
.extern datos            // arreglo con los 30 valores leídos

// ============================================================
.section .data

// Nombre del archivo de salida
nombre_salida:
    .asciz "resultado_varianza.txt"

// ============================================================
// Plantilla del archivo de salida
// Cada XXXX será reemplazado con el valor calculado
// ============================================================
linea_module:
    .asciz "MODULE=VARIANCE\n"
linea_module_len = . - linea_module

linea_total:
    .asciz "TOTAL_VALUES=30\n"
linea_total_len = . - linea_total

// Para las líneas con valores calculados usamos buffers
label_mean:     .asciz "MEAN="
label_mean_len = . - label_mean

label_var:      .asciz "VARIANCE="
label_var_len = . - label_var

label_desv:     .asciz "STD_DEV="
label_desv_len = . - label_desv

newline:        .asciz "\n"
newline_len = . - newline

// Buffer donde construimos el archivo de salida completo
.comm buffer_salida, 512, 8

// Buffers temporales para convertir números a texto
.comm buf_media, 32, 8
.comm buf_var,   32, 8
.comm buf_desv,  32, 8

// ============================================================
.section .text
.global _start

// ============================================================
// INICIO DEL PROGRAMA
// ============================================================
_start:

    // ----------------------------------------------------------
    // PASO 1: Leer los 30 datos de HUM_AIRE (columna 2) desde CSV
    // ----------------------------------------------------------
    mov x0, #2              // columna 2 = HUM_AIRE
    bl leer_datos           // después de esto, 'datos' tiene los 30 valores
    // x0 ahora tiene cuántos datos se leyeron (debe ser 30)

    // ----------------------------------------------------------
    // PASO 2: Calcular la MEDIA (promedio)
    // ----------------------------------------------------------
    // Fórmula: MEDIA = suma de todos los datos / 30
    
    adr x19, datos          // x19 = dirección del arreglo datos
    mov x20, #0             // x20 = acumulador de la suma
    mov x21, #0             // x21 = contador (0 a 29)

.loop_suma:
    cmp x21, #30            // ¿ya sumamos los 30?
    beq .fin_suma           // si sí, salir del loop

    ldr x22, [x19, x21, lsl #3]  // x22 = datos[x21]
    add x20, x20, x22       // suma += datos[x21]
    add x21, x21, #1        // contador++
    b .loop_suma

.fin_suma:
    // x20 = suma total de los 30 datos
    // MEDIA = suma / 30
    mov x23, #30
    udiv x24, x20, x23      // x24 = MEDIA (parte entera)
    // Guardamos la media para usarla después
    // x24 = MEDIA

    // ----------------------------------------------------------
    // PASO 3: Calcular la VARIANZA
    // ----------------------------------------------------------
    // Fórmula: VAR = Σ(dato - media)² / 30
    // 
    // Para cada dato:
    //   1. Restar la media: diferencia = dato - media
    //   2. Elevar al cuadrado: cuadrado = diferencia * diferencia
    //   3. Sumar todos los cuadrados
    // Finalmente dividir entre 30

    mov x25, #0             // x25 = suma de cuadrados
    mov x21, #0             // x21 = contador

.loop_varianza:
    cmp x21, #30
    beq .fin_varianza

    ldr x22, [x19, x21, lsl #3]  // x22 = datos[x21]

    // Calcular diferencia = dato - media
    // Usamos valor absoluto para evitar negativos
    cmp x22, x24            // comparar dato con media
    bge .dato_mayor         // si dato >= media, restar normal

    // dato < media: diferencia = media - dato
    sub x26, x24, x22       // x26 = media - dato
    b .elevar_cuadrado

.dato_mayor:
    // dato >= media: diferencia = dato - media
    sub x26, x22, x24       // x26 = dato - media

.elevar_cuadrado:
    // cuadrado = diferencia * diferencia
    mul x27, x26, x26       // x27 = diferencia²
    add x25, x25, x27       // suma_cuadrados += diferencia²

    add x21, x21, #1        // contador++
    b .loop_varianza

.fin_varianza:
    // x25 = suma de todos los (dato - media)²
    // VARIANZA = suma_cuadrados / 30
    udiv x28, x25, x23      // x28 = VARIANZA (x23 sigue siendo 30)

    // ----------------------------------------------------------
    // PASO 4: Calcular la DESVIACIÓN ESTÁNDAR
    // ----------------------------------------------------------
    // DESV = raíz cuadrada de la varianza
    // 
    // Como ARM64 no tiene instrucción directa de raíz cuadrada
    // para enteros, usamos el método de Newton-Raphson
    // (aproximación iterativa):
    //   estimado = varianza / 2
    //   repetir: estimado = (estimado + varianza/estimado) / 2
    //   hasta que converja

    mov x0, x28             // x0 = varianza
    bl .raiz_cuadrada       // resultado en x0
    mov x29, x0             // x29 = DESVIACIÓN ESTÁNDAR

    // ----------------------------------------------------------
    // PASO 5: Construir el archivo de salida
    // ----------------------------------------------------------
    // El archivo debe verse así:
    //   MODULE=VARIANCE
    //   TOTAL_VALUES=30
    //   MEAN=28
    //   VARIANCE=35
    //   STD_DEV=5

    adr x0, buffer_salida   // x0 = inicio del buffer de salida
    mov x9, #0              // x9 = posición actual en el buffer

    // Escribir "MODULE=VARIANCE\n"
    bl .copiar_module
    
    // Escribir "TOTAL_VALUES=30\n"
    bl .copiar_total

    // Escribir "MEAN=" + valor + "\n"
    bl .copiar_label_mean
    mov x0, x24             // x0 = valor de la media
    adr x1, buf_media
    bl int_a_ascii          // convertir media a texto
    adr x0, buf_media
    bl .copiar_cadena

    // Escribir salto de línea
    bl .copiar_newline

    // Escribir "VARIANCE=" + valor + "\n"
    bl .copiar_label_var
    mov x0, x28             // x0 = valor de la varianza
    adr x1, buf_var
    bl int_a_ascii
    adr x0, buf_var
    bl .copiar_cadena
    bl .copiar_newline

    // Escribir "STD_DEV=" + valor + "\n"
    bl .copiar_label_desv
    mov x0, x29             // x0 = desviación estándar
    adr x1, buf_desv
    bl int_a_ascii
    adr x0, buf_desv
    bl .copiar_cadena
    bl .copiar_newline

    // ----------------------------------------------------------
    // PASO 6: Escribir el buffer en el archivo .txt
    // ----------------------------------------------------------
    // Abrir archivo de salida
    mov x8, #56             // syscall openat
    mov x0, #-100           // AT_FDCWD
    adr x1, nombre_salida
    mov x2, #577            // O_WRONLY | O_CREAT | O_TRUNC
    mov x3, #0644           // permisos
    svc #0
    mov x10, x0             // x10 = descriptor del archivo

    // Escribir el contenido
    mov x8, #64             // syscall write
    mov x0, x10
    adr x1, buffer_salida
    mov x2, x9              // x9 = cuántos bytes escribimos
    svc #0

    // Cerrar el archivo
    mov x8, #57             // syscall close
    mov x0, x10
    svc #0

    // ----------------------------------------------------------
    // PASO 7: Imprimir también en pantalla (para verificar)
    // ----------------------------------------------------------
    mov x8, #64             // syscall write
    mov x0, #1              // stdout
    adr x1, buffer_salida
    mov x2, x9
    svc #0

    // ----------------------------------------------------------
    // FIN DEL PROGRAMA
    // ----------------------------------------------------------
    mov x8, #93             // syscall exit
    mov x0, #0              // código de salida 0 = éxito
    svc #0


// ============================================================
// FUNCIÓN: .raiz_cuadrada
// Calcula la raíz cuadrada entera usando Newton-Raphson
// Parámetro: x0 = número
// Retorna:   x0 = raíz cuadrada entera aproximada
// ============================================================
.raiz_cuadrada:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    str x20, [sp, #24]

    mov x19, x0             // guardar el número original

    // Caso especial: raíz de 0 = 0
    cmp x19, #0
    beq .raiz_cero

    // Estimado inicial = número / 2
    lsr x20, x19, #1        // x20 = estimado (desplazamiento = dividir entre 2)
    
    // Si el número es 1, la raíz es 1
    cmp x20, #0
    beq .raiz_uno

.loop_newton:
    // nuevo_estimado = (estimado + numero/estimado) / 2
    udiv x0, x19, x20       // x0 = numero / estimado
    add x0, x0, x20         // x0 = estimado + numero/estimado
    lsr x0, x0, #1          // x0 = (estimado + numero/estimado) / 2

    // ¿Convergió? Si nuevo_estimado >= estimado, terminamos
    cmp x0, x20
    bge .raiz_lista

    mov x20, x0             // actualizar estimado
    b .loop_newton

.raiz_lista:
    mov x0, x20             // retornar estimado actual
    b .fin_raiz

.raiz_cero:
    mov x0, #0
    b .fin_raiz

.raiz_uno:
    mov x0, #1

.fin_raiz:
    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret


// ============================================================
// FUNCIONES AUXILIARES para construir el buffer de salida
// Todas usan x9 como posición actual en buffer_salida
// ============================================================

.copiar_module:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, linea_module
.loop_cm:
    ldrb w2, [x1]
    cmp w2, #0
    beq .fin_cm
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b .loop_cm
.fin_cm:
    ldp x29, x30, [sp], #16
    ret

.copiar_total:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, linea_total
.loop_ct:
    ldrb w2, [x1]
    cmp w2, #0
    beq .fin_ct
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b .loop_ct
.fin_ct:
    ldp x29, x30, [sp], #16
    ret

.copiar_label_mean:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, label_mean
.loop_clm:
    ldrb w2, [x1]
    cmp w2, #0
    beq .fin_clm
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b .loop_clm
.fin_clm:
    ldp x29, x30, [sp], #16
    ret

.copiar_label_var:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, label_var
.loop_clv:
    ldrb w2, [x1]
    cmp w2, #0
    beq .fin_clv
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b .loop_clv
.fin_clv:
    ldp x29, x30, [sp], #16
    ret

.copiar_label_desv:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, label_desv
.loop_cld:
    ldrb w2, [x1]
    cmp w2, #0
    beq .fin_cld
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b .loop_cld
.fin_cld:
    ldp x29, x30, [sp], #16
    ret

.copiar_cadena:
    // x0 = puntero a la cadena a copiar
    stp x29, x30, [sp, #-16]!
    mov x1, x0
    adr x0, buffer_salida
.loop_cc:
    ldrb w2, [x1]
    cmp w2, #0
    beq .fin_cc
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b .loop_cc
.fin_cc:
    ldp x29, x30, [sp], #16
    ret

.copiar_newline:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    mov w2, #10             // ASCII '\n'
    strb w2, [x0, x9]
    add x9, x9, #1
    ldp x29, x30, [sp], #16
    ret


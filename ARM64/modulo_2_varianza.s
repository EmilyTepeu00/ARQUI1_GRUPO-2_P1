// ============================================================
// modulo_2_varianza.s
// Jackeline Stephany Rivera Argueta - 202401685
// Módulo 2: Varianza y Desviación Estándar
// Curso: ACYE1 - Segundo Semestre 2026
// 
// Lo que hace este modulo:
//   1. Se leen los 30 datos de Humedad del Aire desde lecturas.csv
//   2. Calculo que tan dispersos estan esos datos respecto al promedio
//    y escribo los resultados en un archivo resultado_varianza.txt
//
// Fórmulas:
//   MEDIA = ΣX / N
//   VAR   = Σ(X - MEDIA)² / N
//   DESV  = √VAR
//
// Donde N = 30
// ============================================================

// Estas funciones viven en utils.s, las llamo desde aca
.extern leer_datos       // esta lee el CSV y me llena el arreglo datos
.extern int_a_ascii      // convierte un numero a texto para escribirlo
.extern ascii_a_int      // convierte texto a número
.extern datos            // arreglo con los 30 valores

// ===========================================================
// Aqui guardo los textos fijos que van en el archivo de salida
// ===========================================================
.section .data

nombre_salida:
    .asciz "resultado_varianza.txt"

// estas son las lineas que siempre van igual en el resultado
linea_module:
    .asciz "MODULE=VARIANCE\n"
linea_module_len = . - linea_module

linea_total:
    .asciz "TOTAL_VALUES=30\n"
linea_total_len = . - linea_total

// estos son los "titulos" antes de cada valor calculado
label_mean:     .asciz "MEAN="
label_mean_len = . - label_mean

label_var:      .asciz "VARIANCE="
label_var_len = . - label_var

label_desv:     .asciz "STD_DEV="
label_desv_len = . - label_desv

newline:        .asciz "\n"
newline_len = . - newline

// Aquí se va armando todo el texto del archivo antes de guardarlo
.comm buffer_salida, 512, 8

// Estos son los espacios temporales para convertir numeros a texto
.comm buf_media, 32, 8
.comm buf_var,   32, 8
.comm buf_desv,  32, 8

// ===========================================================
// Aca empieza el codigo que se ejecuta
// ===========================================================
.section .text
.global _start

// Se inicia el programa
_start:

    // ----------------------------------------------------------
    // PASO 1: le digo a utils que me traiga la columna 2 (HUM_AIRE)
    // El 2 es el numero de columna en el CSV (empieza desde 0)
    // ----------------------------------------------------------
    mov x0, #2              // columna 2 = HUM_AIRE
    bl leer_datos           // después de esto, 'datos' tiene los 30 valores

    // ----------------------------------------------------------
    // PASO 2: Calcular la media (promedio de los 30 datos)
    // formula: MEDIA = suma de todos / 3
    // ----------------------------------------------------------    
    adr x19, datos          // x19 apunta al inicio del arreglo datos
    mov x20, #0             // x20 va acumulando la suma, arranco en 0
    mov x21, #0             // x21 es mi contador, va de 0 a 29

// este loop suma los 30 datos uno por uno
.loop_suma:
    cmp x21, #30            // ¿ya sumamos los 30?
    beq .fin_suma           // si ya, salgo del loop

    ldr x22, [x19, x21, lsl #3] // agarro datos[x21], el lsl#3 es x8 porque cada numero ocupa 8 bytes
    add x20, x20, x22       // suma el dato acumulador
    add x21, x21, #1        // avanzo a la siguiente (incremento)
    b .loop_suma

.fin_suma:
    // ya tengo la suma de x20, ahora divido entre 30
    mov x23, #30
    udiv x24, x20, x23      // x24 = media = suma / 30
    // Guardamos la media para usarla después
    // x24 = media

    // ---------------------------------------------------------
    // Paso 3: calculo la varianza
    // formula: VAR = suma de (dato - media)^2 / 30
    // para cada dato: le resto la media, lo elevo al cuadrado
    // y voy sumando todos esos cuadrados
    // ---------------------------------------------------------
    mov x25, #0             // x25 acumula la suma de cuadrados
    mov x21, #0             // reinicio el contador

.loop_varianza:
    cmp x21, #30
    beq .fin_varianza

    ldr x22, [x19, x21, lsl #3]  // tomo datos[x21]

    // necesito (dato - media) pero siempre positivo
    // entonces reviso cual es mayor y resto el menor del mayor
    cmp x22, x24            // comparo dato con media
    bge .dato_mayor         // si dato >= media, restar normal

    // caso: dato < media, entonces diferencia = media - dato
    sub x26, x24, x22       
    b .elevar_cuadrado

.dato_mayor:
    // caso: dato >= media, entonces diferencia = dato - media
    sub x26, x22, x24       // x26 = dato - media

.elevar_cuadrado:
    mul x27, x26, x26       // cuadrado = diferencia * diferencia
    add x25, x25, x27       // sumo ese cuadrado al acumulaodor

    add x21, x21, #1        // contador++
    b .loop_varianza

.fin_varianza:
    // ya tengo la suma de cuadrados en x25
    udiv x28, x25, x23      // x28 = varianza = suma_cuadrados / 30

    // ---------------------------------------------------------
    // Paso 4: calculo la desviacion estandar = raiz(varianza)
    // ARM64 no tiene instruccion para raiz cuadrada de enteros
    // asi que use el metodo de Newton-Raphson que va mejorando
    // un estimado hasta llegar a la respuesta correcta
    // ---------------------------------------------------------
    mov x0, x28             // le paso la varianza a la función
    bl .raiz_cuadrada       // resultado regresa en x0
    mov x29, x0             // guardo la desviacio en x29

    // ---------------------------------------------------------
    // Paso 5: armo el texto del archivo de salida en el buffer
    // voy copiando pedacito por pedacito usando x9 como posicion
    // ---------------------------------------------------------
    // El archivo debe verse así:
    //   MODULE=VARIANCE
    //   TOTAL_VALUES=30
    //   MEAN=64
    //   VARIANCE=162
    //   STD_DEV=12

    adr x0, buffer_salida   
    mov x9, #0              // x9 es donde voy escribiendo en el buffer

    bl .copiar_module       // escribe "MODULE=VARIANCE\n"
    bl .copiar_total        // escribe "TOTAL_VALUES=30\n"

    // Escribir "MEAN=" + el valor calculado + salto de línea
    bl .copiar_label_mean
    mov x0, x24             // x0 = valor de la media
    adr x1, buf_media
    bl int_a_ascii          // convertir el numero a texto
    adr x0, buf_media
    bl .copiar_cadena
    bl .copiar_newline       // escribe salto de línea

    // Escribir "VARIANCE=" + el valor + salto de linea
    bl .copiar_label_var
    mov x0, x28             // x0 = valor de la varianza
    adr x1, buf_var
    bl int_a_ascii
    adr x0, buf_var
    bl .copiar_cadena
    bl .copiar_newline

    // Escribir "STD_DEV=" + el valor + salto de línea
    bl .copiar_label_desv
    mov x0, x29             // x0 = desviación estándar
    adr x1, buf_desv
    bl int_a_ascii
    adr x0, buf_desv
    bl .copiar_cadena
    bl .copiar_newline

    // ---------------------------------------------------------
    // Paso 6: guardo el buffer en el archivo resultado_varianza.txt
    // uso syscalls para pedirle al sistema que haga las operaciones
    // ---------------------------------------------------------
    // Abro/creo el archivo de salida
    mov x8, #56             // syscall 56 = openat (abrir archivo
    mov x0, #-100           // AT_FDCWD = buscar en directorio actual
    adr x1, nombre_salida
    mov x2, #577            // // flags: crear si no existe y limpiar contenido anterior
    mov x3, #0644           // permisos del archivo en linux
    svc #0
    mov x10, x0             // guardo el descriptor del archivo

    // Escribir el contenido del buffer en el archivo
    mov x8, #64             // syscall 64 = write (escribir)
    mov x0, x10             // descriptor del archivo
    adr x1, buffer_salida
    mov x2, x9              // x9 tiene cuantos bytes escribi en el buffer
    svc #0

    // Cerrar el archivo
    mov x8, #57             // syscall 57 = close (cerrar)
    mov x0, x10
    svc #0

    // ---------------------------------------------------------
    // Paso 7: tambien muestro los resultados en la pantalla
    // es lo mismo que escribir al archivo pero con fd=1 (stdout)
    // ---------------------------------------------------------
    mov x8, #64             
    mov x0, #1              // 1 = stdout = pantalla
    adr x1, buffer_salida
    mov x2, x9
    svc #0

    // ----------------------------------------------------------
    // Fin del programa, salgo con codigo 0 = todo bien
    // ----------------------------------------------------------
    mov x8, #93             // syscall 93 = exit
    mov x0, #0              // código de salida 0 = éxito
    svc #0


// ===========================================================
// raiz_cuadrada
// Calcula la raiz cuadrada entera usando Newton-Raphson
// Le paso el numero en x0 y me devuelve la raiz en x0
//
// Como funciona Newton-Raphson:
//   arranco con un estimado = numero / 2
//   cada vuelta mejoro el estimado: nuevo = (estimado + numero/estimado) / 2
//   cuando el nuevo estimado ya no mejora, ese es el resultado
// ============================================================
.raiz_cuadrada:
    stp x29, x30, [sp, #-32]!      // guardo registros en la pila
    mov x29, sp
    str x19, [sp, #16]
    str x20, [sp, #24]

    mov x19, x0             // guardar el número original

    // Caso especial: raíz de 0 = 0
    cmp x19, #0
    beq .raiz_cero

    // Estimado inicial = número / 2 (lsr #1 es dividir entre 2 con bits)
    lsr x20, x19, #1        // x20 = estimado (desplazamiento = dividir entre 2)
    
    // si el estimado quedo en 0, la raiz es 1
    cmp x20, #0
    beq .raiz_uno

.loop_newton:
    udiv x0, x19, x20       // x0 = numero / estimado_actual
    add x0, x0, x20         // x0 = x0 + estimado_actual
    lsr x0, x0, #1          // x0 = x0 / 2 (nuevo estimado)

    // si el nuevo estimado es mayor o igual al anterior ya convergio
    cmp x0, x20
    bge .raiz_lista

    mov x20, x0             // actualizar el estimado y repito
    b .loop_newton

.raiz_lista:
    mov x0, x20             // retorno el estimado final
    b .fin_raiz

.raiz_cero:
    mov x0, #0
    b .fin_raiz

.raiz_uno:
    mov x0, #1

.fin_raiz:
    ldr x19, [sp, #16]      // recupero los registros guardados
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret


// ===========================================================
// funciones para copiar texto al buffer de salida
// todas usan x9 como posicion actual en el buffer
// x9 va creciendo conforme escribo mas cosas
// ===========================================================

.copiar_module:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, linea_module
.loop_cm:
    ldrb w2, [x1]            // leo un byte del texto fuente
    cmp w2, #0               // es el fin del texto?
    beq .fin_cm
    strb w2, [x0, x9]        // lo copio al buffer en la posicion x9
    add x9, x9, #1           // avanzo en el buffer
    add x1, x1, #1           // avanzo en el texto fuente
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
    // recibe en x0 el puntero al texto que quiero copiar
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
    mov w2, #10             // 10 es el codigo ASCII del salto de linea \n
    strb w2, [x0, x9]
    add x9, x9, #1
    ldp x29, x30, [sp], #16
    ret


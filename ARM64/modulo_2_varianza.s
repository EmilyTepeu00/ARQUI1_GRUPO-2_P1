// ===========================================================
// modulo_2_varianza.s
// Jackeline Stephany Rivera Argueta - 202401685
// Modulo 2: Varianza y Desviacion Estandar
// Curso: ACYE1 - Segundo Semestre 2026
//
// Lee la columna que el usuario seleccione desde el dashboard.
// El numero de columna llega como argv[1] cuando Python ejecuta
// el binario. Si no viene argumento, usa columna 3 (HUM_AIRE).
//
// Formulas:
//   MEDIA = suma de todo / 30
//   VAR   = suma de (dato-media)^2 / 30
//   DESV  = raiz(VAR)
//
// Archivo de entrada:  lecturas.csv
// Archivo de salida:   resultado_varianza.txt
// ===========================================================

.extern leer_datos
.extern int_a_ascii
.extern ascii_a_int
.extern datos

.section .data

nombre_salida:
    .asciz "resultado_varianza.txt"

linea_module:
    .asciz "MODULE=VARIANCE\n"
linea_module_len = . - linea_module

linea_total:
    .asciz "TOTAL_VALUES=30\n"
linea_total_len = . - linea_total

label_mean:     .asciz "MEAN="
label_mean_len = . - label_mean

label_var:      .asciz "VARIANCE="
label_var_len = . - label_var

label_desv:     .asciz "STD_DEV="
label_desv_len = . - label_desv

newline:        .asciz "\n"
newline_len = . - newline

.comm buffer_salida, 512, 8
.comm buf_media, 32, 8
.comm buf_var,   32, 8
.comm buf_desv,  32, 8

.section .text
.global _start

_start:
    // --------------------------------------------------------
    // LECTURA DE argv[1]: el numero de columna que manda Python
    // [sp]    = argc
    // [sp+16] = puntero al string de argv[1] (ej: "7" para GAS)
    // Si no viene argumento usamos columna 3 (HUM_AIRE) por defecto
    // --------------------------------------------------------
    ldr x0, [sp]            // x0 = argc
    cmp x0, #2              // hay al menos 1 argumento?
    blt .usar_default_2     // no -> ir al default

    ldr x0, [sp, #16]       // x0 = puntero a argv[1]
    bl  ascii_a_int          // convierte el string a numero entero en x0
    b   .llamar_leer_2

.usar_default_2:
    mov x0, #3              // default: columna 3 = HUM_AIRE

.llamar_leer_2:
    // leer_datos llena datos[] con los 30 valores de la columna x0
    bl leer_datos

    // --------------------------------------------------------
    // PASO 1: calcular la media (MEDIA = suma / 30)
    // x19 = puntero a datos[]
    // x20 = acumulador de suma
    // x21 = contador i
    // --------------------------------------------------------
    adr x19, datos
    mov x20, #0
    mov x21, #0

loop_suma:
    cmp x21, #30
    beq fin_suma

    ldr x22, [x19, x21, lsl #3]
    add x20, x20, x22
    add x21, x21, #1
    b loop_suma

fin_suma:
    mov x23, #30
    udiv x24, x20, x23      // x24 = MEDIA

    // --------------------------------------------------------
    // PASO 2: calcular la varianza VAR = suma((dato-media)^2) / 30
    // Usamos valor absoluto para evitar negativos antes de elevar
    // --------------------------------------------------------
    mov x25, #0             // x25 = acumulador de suma de cuadrados
    mov x21, #0

loop_varianza:
    cmp x21, #30
    beq fin_varianza

    ldr x22, [x19, x21, lsl #3]

    // calcular |dato - media| sin negativos
    cmp x22, x24
    bge dato_mayor

    sub x26, x24, x22       // dato < media: diferencia = media - dato
    b elevar_cuadrado

dato_mayor:
    sub x26, x22, x24       // dato >= media: diferencia = dato - media

elevar_cuadrado:
    mul x27, x26, x26       // cuadrado = diferencia^2
    add x25, x25, x27       // acumulo

    add x21, x21, #1
    b loop_varianza

fin_varianza:
    udiv x28, x25, x23      // x28 = VARIANZA = suma_cuadrados / 30

    // --------------------------------------------------------
    // PASO 3: desviacion estandar = raiz(varianza)
    // Metodo Newton-Raphson para raiz cuadrada entera
    // --------------------------------------------------------
    mov x0, x28
    bl raiz_cuadrada        // resultado en x0
    mov x29, x0             // x29 = STD_DEV

    // --------------------------------------------------------
    // ARMAR EL TEXTO en buffer_salida usando x9 como posicion
    // --------------------------------------------------------
    adr x0, buffer_salida
    mov x9, #0

    bl copiar_module
    bl copiar_total

    // MEAN=valor
    bl copiar_label_mean
    mov x0, x24
    adr x1, buf_media
    bl int_a_ascii
    adr x0, buf_media
    bl copiar_cadena
    bl copiar_newline

    // VARIANCE=valor
    bl copiar_label_var
    mov x0, x28
    adr x1, buf_var
    bl int_a_ascii
    adr x0, buf_var
    bl copiar_cadena
    bl copiar_newline

    // STD_DEV=valor
    bl copiar_label_desv
    mov x0, x29
    adr x1, buf_desv
    bl int_a_ascii
    adr x0, buf_desv
    bl copiar_cadena
    bl copiar_newline

    // --------------------------------------------------------
    // ESCRIBIR AL ARCHIVO resultado_varianza.txt
    // --------------------------------------------------------
    mov x8, #56
    mov x0, #-100
    adr x1, nombre_salida
    mov x2, #577
    mov x3, #0644
    svc #0
    mov x10, x0

    mov x8, #64
    mov x0, x10
    adr x1, buffer_salida
    mov x2, x9
    svc #0

    mov x8, #57
    mov x0, x10
    svc #0

    // MOSTRAR EN TERMINAL
    mov x8, #64
    mov x0, #1
    adr x1, buffer_salida
    mov x2, x9
    svc #0

    mov x8, #93
    mov x0, #0
    svc #0


// ============================================================
// raiz_cuadrada: Newton-Raphson para raiz entera
// Entrada: x0 = numero
// Salida:  x0 = raiz entera
// ============================================================
raiz_cuadrada:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    str x20, [sp, #24]

    mov x19, x0

    cmp x19, #0
    beq raiz_es_cero

    lsr x20, x19, #1        // estimado inicial = numero / 2

    cmp x20, #0
    beq raiz_es_uno

loop_newton:
    udiv x0, x19, x20
    add x0, x0, x20
    lsr x0, x0, #1          // nuevo estimado = (estimado + num/estimado) / 2

    cmp x0, x20
    bge raiz_lista          // si no mejora, convergio

    mov x20, x0
    b loop_newton

raiz_lista:
    mov x0, x20
    b fin_raiz

raiz_es_cero:
    mov x0, #0
    b fin_raiz

raiz_es_uno:
    mov x0, #1

fin_raiz:
    ldr x19, [sp, #16]
    ldr x20, [sp, #24]
    ldp x29, x30, [sp], #32
    ret


// ---- funciones auxiliares para copiar texto al buffer ----

copiar_module:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, linea_module
loop_cm:
    ldrb w2, [x1]
    cmp w2, #0
    beq fin_cm
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b loop_cm
fin_cm:
    ldp x29, x30, [sp], #16
    ret

copiar_total:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, linea_total
loop_ct:
    ldrb w2, [x1]
    cmp w2, #0
    beq fin_ct
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b loop_ct
fin_ct:
    ldp x29, x30, [sp], #16
    ret

copiar_label_mean:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, label_mean
loop_clm:
    ldrb w2, [x1]
    cmp w2, #0
    beq fin_clm
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b loop_clm
fin_clm:
    ldp x29, x30, [sp], #16
    ret

copiar_label_var:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, label_var
loop_clv:
    ldrb w2, [x1]
    cmp w2, #0
    beq fin_clv
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b loop_clv
fin_clv:
    ldp x29, x30, [sp], #16
    ret

copiar_label_desv:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, label_desv
loop_cld:
    ldrb w2, [x1]
    cmp w2, #0
    beq fin_cld
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b loop_cld
fin_cld:
    ldp x29, x30, [sp], #16
    ret

copiar_cadena:
    stp x29, x30, [sp, #-16]!
    mov x1, x0
    adr x0, buffer_salida
loop_cc:
    ldrb w2, [x1]
    cmp w2, #0
    beq fin_cc
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b loop_cc
fin_cc:
    ldp x29, x30, [sp], #16
    ret

copiar_newline:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    mov w2, #10
    strb w2, [x0, x9]
    add x9, x9, #1
    ldp x29, x30, [sp], #16
    ret

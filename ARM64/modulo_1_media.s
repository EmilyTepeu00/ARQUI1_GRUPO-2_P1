// ============================================================
// modulo_1_media.s
// Integrante 1 - Media Aritmetica Ponderada
// Curso: ACYE1 - Vacaciones Junio 2026
//
// Leo la columna TEMP (columna 1) del archivo lecturas.csv
// y calculo la media ponderada donde cada dato tiene un peso
// distinto: el primero tiene peso 1, el segundo peso 2, etc.
//
// La formula que uso es:
//   MEDIA_PONDERADA = S(Xi * Wi) / SWi   donde Wi va de 1 a 30
//
// Para leer el CSV uso leer_datos de utils.s
// Para convertir numeros a texto uso int_a_ascii de utils.s
// Los datos quedan en el arreglo datos[] de utils.s
// ============================================================

.extern leer_datos
.extern int_a_ascii
.extern datos

.section .data

nombre_salida:
    .asciz "resultado_media.txt"

// estas son las lineas fijas que siempre van en el resultado
linea_module:
    .asciz "MODULE=WEIGHTED_MEAN\n"
linea_module_len = . - linea_module

linea_total:
    .asciz "TOTAL_VALUES=30\n"
linea_total_len = . - linea_total

// estos son los "titulos" antes de cada valor calculado
label_sumx:     .asciz "SUM_X="
label_sumx_len = . - label_sumx

label_wsum:     .asciz "WEIGHT_SUM="
label_wsum_len = . - label_wsum

label_mean:     .asciz "WEIGHTED_MEAN="
label_mean_len = . - label_mean

.section .bss

// aqui armo todo el texto antes de escribirlo al archivo
buffer_salida:  .skip 512

// buffers para convertir cada numero a texto
buf_sumx:   .skip 32
buf_wsum:   .skip 32
buf_media:  .skip 32

.section .text
.global _start

_start:
    // le pido a utils que lea la columna 1 (TEMP) del CSV
    // despues de esto datos[] ya tiene los 30 valores listos
    mov x0, #1
    bl leer_datos

    // inicializo los registros que voy a usar en el calculo
    // x19 apunta al arreglo datos[]
    // x20 acumula la suma simple SUM_X
    // x21 es el indice i que va de 0 a 29
    // x22 acumula la suma ponderada S(Xi * Wi)
    // x23 acumula la suma de pesos S(Wi) = 1+2+...+30 = 465
    // x24 es el peso actual Wi, arranca en 1 y sube hasta 30
    adr x19, datos
    mov x20, #0
    mov x21, #0
    mov x22, #0
    mov x23, #0
    mov x24, #1

.loop_media:
    cmp x21, #30
    beq .fin_media

    ldr x25, [x19, x21, lsl #3]    // cargo datos[i]
    add x20, x20, x25              // SUM_X += datos[i]
    mul x26, x25, x24              // Xi * Wi
    add x22, x22, x26              // suma_ponderada += Xi * Wi
    add x23, x23, x24              // suma_pesos += Wi
    add x21, x21, #1               // i++
    add x24, x24, #1               // Wi++
    b .loop_media

.fin_media:
    // divido la suma ponderada entre la suma de pesos
    udiv x27, x22, x23             // x27 = WEIGHTED_MEAN

    // empiezo a armar el texto en buffer_salida
    // x9 marca hasta donde he escrito
    mov x9, #0

    bl .copiar_module
    bl .copiar_total

    // escribo SUM_X=valor
    bl .copiar_label_sumx
    mov x0, x20
    adr x1, buf_sumx
    bl int_a_ascii
    adr x0, buf_sumx
    bl .copiar_cadena
    bl .copiar_newline

    // escribo WEIGHT_SUM=valor
    bl .copiar_label_wsum
    mov x0, x23
    adr x1, buf_wsum
    bl int_a_ascii
    adr x0, buf_wsum
    bl .copiar_cadena
    bl .copiar_newline

    // escribo WEIGHTED_MEAN=valor
    bl .copiar_label_mean
    mov x0, x27
    adr x1, buf_media
    bl int_a_ascii
    adr x0, buf_media
    bl .copiar_cadena
    bl .copiar_newline

    // creo o sobreescribo el archivo resultado_media.txt
    mov x8, #56             // syscall openat
    mov x0, #-100           // AT_FDCWD = directorio actual
    adr x1, nombre_salida
    mov x2, #577            // crear si no existe, borrar contenido anterior
    mov x3, #0644           // permisos rw-r--r--
    svc #0
    mov x10, x0             // guardo el descriptor del archivo

    // escribo el buffer al archivo
    mov x8, #64
    mov x0, x10
    adr x1, buffer_salida
    mov x2, x9
    svc #0

    // cierro el archivo
    mov x8, #57
    mov x0, x10
    svc #0

    // tambien muestro el resultado en la terminal
    mov x8, #64
    mov x0, #1              // 1 = stdout = pantalla
    adr x1, buffer_salida
    mov x2, x9
    svc #0

    // fin del programa con codigo 0 = todo salio bien
    mov x8, #93
    mov x0, #0
    svc #0


// estas funciones copian texto al buffer_salida
// todas usan x9 como posicion actual, que va creciendo

.copiar_module:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, linea_module
.lp_mod:
    ldrb w2, [x1]
    cmp w2, #0
    beq .fin_mod
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b .lp_mod
.fin_mod:
    ldp x29, x30, [sp], #16
    ret

.copiar_total:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, linea_total
.lp_tot:
    ldrb w2, [x1]
    cmp w2, #0
    beq .fin_tot
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b .lp_tot
.fin_tot:
    ldp x29, x30, [sp], #16
    ret

.copiar_label_sumx:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, label_sumx
.lp_lsx:
    ldrb w2, [x1]
    cmp w2, #0
    beq .fin_lsx
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b .lp_lsx
.fin_lsx:
    ldp x29, x30, [sp], #16
    ret

.copiar_label_wsum:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, label_wsum
.lp_lws:
    ldrb w2, [x1]
    cmp w2, #0
    beq .fin_lws
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b .lp_lws
.fin_lws:
    ldp x29, x30, [sp], #16
    ret

.copiar_label_mean:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    adr x1, label_mean
.lp_lmn:
    ldrb w2, [x1]
    cmp w2, #0
    beq .fin_lmn
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b .lp_lmn
.fin_lmn:
    ldp x29, x30, [sp], #16
    ret

// esta recibe en x0 el puntero al texto que quiero copiar
.copiar_cadena:
    stp x29, x30, [sp, #-16]!
    mov x1, x0
    adr x0, buffer_salida
.lp_cad:
    ldrb w2, [x1]
    cmp w2, #0
    beq .fin_cad
    strb w2, [x0, x9]
    add x9, x9, #1
    add x1, x1, #1
    b .lp_cad
.fin_cad:
    ldp x29, x30, [sp], #16
    ret

// escribe el salto de linea al final de cada valor
.copiar_newline:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    mov w2, #10             // 10 es el codigo ASCII de '\n'
    strb w2, [x0, x9]
    add x9, x9, #1
    ldp x29, x30, [sp], #16
    ret
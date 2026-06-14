// ============================================================
// modulo_1_media.s
// Integrante 1 - Media Aritmetica Ponderada
// Curso: ACYE1 - Vacaciones Junio 2026
//
// Leo la columna que el usuario seleccione desde el dashboard.
// El numero de columna llega como argv[1] cuando Python ejecuta
// el binario. Si no viene argumento, uso columna 2 (TEMP) por defecto.
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

linea_module:
    .asciz "MODULE=WEIGHTED_MEAN\n"
linea_module_len = . - linea_module

linea_total:
    .asciz "TOTAL_VALUES=30\n"
linea_total_len = . - linea_total

label_sumx:     .asciz "SUM_X="
label_sumx_len = . - label_sumx

label_wsum:     .asciz "WEIGHT_SUM="
label_wsum_len = . - label_wsum

label_mean:     .asciz "WEIGHTED_MEAN="
label_mean_len = . - label_mean

.section .bss

buffer_salida:  .skip 512
buf_sumx:   .skip 32
buf_wsum:   .skip 32
buf_media:  .skip 32

.section .text
.global _start

_start:
    // --------------------------------------------------------
    // LECTURA DE argv[1]: el numero de columna que manda Python
    // Al arrancar el programa, [sp] tiene argc y [sp+16] tiene
    // un puntero al string de argv[1] (ej: "6" para GAS)
    // Si no viene argumento usamos columna 2 (TEMP) por defecto
    // --------------------------------------------------------
    ldr x0, [sp]            // x0 = argc
    cmp x0, #2              // hay al menos 1 argumento?
    blt .usar_default_1     // no -> ir al default

    ldr x0, [sp, #16]       // x0 = puntero a argv[1] (string "2","3","6"...)
    bl  ascii_a_int          // convierte el string a numero entero en x0
    b   .llamar_leer_1       // ir a llamar leer_datos con ese numero

.usar_default_1:
    mov x0, #2              // default: columna 2 = TEMP (1-based en nuevo utils)

.llamar_leer_1:
    // x0 ya tiene el numero de columna correcto
    // leer_datos llena el arreglo datos[] con los 30 valores de esa columna
    bl leer_datos

    // --------------------------------------------------------
    // CALCULO de media ponderada con pesos Wi = 1, 2, 3 ... 30
    // x19 = puntero a datos[]
    // x20 = SUM_X  (suma simple de todos los datos)
    // x21 = indice i, va de 0 a 29
    // x22 = suma_ponderada S(Xi * Wi)
    // x23 = suma_pesos S(Wi) = 465
    // x24 = peso actual Wi, arranca en 1
    // --------------------------------------------------------
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
    // MEDIA_PONDERADA = suma_ponderada / suma_pesos
    udiv x27, x22, x23             // x27 = WEIGHTED_MEAN

    // --------------------------------------------------------
    // ARMAR EL TEXTO en buffer_salida
    // x9 marca hasta donde hemos escrito en el buffer
    // --------------------------------------------------------
    mov x9, #0

    bl .copiar_module
    bl .copiar_total

    // SUM_X=valor
    bl .copiar_label_sumx
    mov x0, x20
    adr x1, buf_sumx
    bl int_a_ascii
    adr x0, buf_sumx
    bl .copiar_cadena
    bl .copiar_newline

    // WEIGHT_SUM=valor
    bl .copiar_label_wsum
    mov x0, x23
    adr x1, buf_wsum
    bl int_a_ascii
    adr x0, buf_wsum
    bl .copiar_cadena
    bl .copiar_newline

    // WEIGHTED_MEAN=valor
    bl .copiar_label_mean
    mov x0, x27
    adr x1, buf_media
    bl int_a_ascii
    adr x0, buf_media
    bl .copiar_cadena
    bl .copiar_newline

    // --------------------------------------------------------
    // ESCRIBIR AL ARCHIVO resultado_media.txt
    // --------------------------------------------------------
    mov x8, #56             // syscall openat
    mov x0, #-100           // AT_FDCWD
    adr x1, nombre_salida
    mov x2, #577            // O_WRONLY|O_CREAT|O_TRUNC
    mov x3, #0644
    svc #0
    mov x10, x0             // x10 = descriptor del archivo

    mov x8, #64             // syscall write
    mov x0, x10
    adr x1, buffer_salida
    mov x2, x9
    svc #0

    mov x8, #57             // syscall close
    mov x0, x10
    svc #0

    // MOSTRAR EN TERMINAL (stdout = fd 1)
    mov x8, #64
    mov x0, #1
    adr x1, buffer_salida
    mov x2, x9
    svc #0

    // FIN DEL PROGRAMA con codigo 0 = exito
    mov x8, #93
    mov x0, #0
    svc #0


// ---- funciones auxiliares para copiar texto al buffer ----

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

.copiar_newline:
    stp x29, x30, [sp, #-16]!
    adr x0, buffer_salida
    mov w2, #10
    strb w2, [x0, x9]
    add x9, x9, #1
    ldp x29, x30, [sp], #16
    ret

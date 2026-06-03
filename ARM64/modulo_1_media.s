// ============================================================
// modulo_1_media.s - Media Aritmetica Ponderada
// Proyecto: Invernadero Inteligente IoT
// Integrante 1
// ============================================================
// Calcula la media ponderada de 30 datos usando pesos 1..30
// Formula: MEDIA_PONDERADA = S(X_i * W_i) / SW_i
//
// Entrada:  lecturas.csv  columna 1 = TEMP
// Salida:   resultado_media.txt
// ============================================================

.equ SYS_OPENAT,  56
.equ SYS_CLOSE,   57
.equ SYS_WRITE,   64
.equ SYS_EXIT,    93
.equ AT_FDCWD,   -100
.equ O_WRONLY,    1
.equ O_CREAT,     64
.equ O_TRUNC,     512
.equ PERM_644,    0644

// ============================================================
.section .data

nombre_salida:
    .asciz "resultado_media.txt"

// Lineas del archivo de salida
linea_module:
    .ascii "MODULE=WEIGHTED_MEAN\n"
    .equ linea_module_len, . - linea_module

linea_total:
    .ascii "TOTAL_VALUES=30\n"
    .equ linea_total_len, . - linea_total

etiq_sumx:
    .ascii "SUM_X="
    .equ etiq_sumx_len, . - etiq_sumx

etiq_wsum:
    .ascii "WEIGHT_SUM="
    .equ etiq_wsum_len, . - etiq_wsum

etiq_mean:
    .ascii "WEIGHTED_MEAN="
    .equ etiq_mean_len, . - etiq_mean

newline:
    .ascii "\n"

// ============================================================
.section .bss

suma_x:         .skip 8     // suma simple de datos
suma_pond:      .skip 8     // suma ponderada S(Xi*Wi)
suma_pesos:     .skip 8     // suma de pesos S(Wi)
media_pond:     .skip 8     // resultado final
buf_num:        .skip 32    // buffer para numero en texto
fd_out:         .skip 8     // descriptor archivo salida

// ============================================================
.section .text

.global _start

// Importar de utils.s
.extern leer_datos
.extern int_a_ascii
.extern datos

// ============================================================
// PUNTO DE ENTRADA
// ============================================================
_start:

    // -------------------------------------------------------
    // PASO 1: Leer columna TEMP (columna 1) del CSV
    // -------------------------------------------------------
    mov x0, #1
    bl  leer_datos
    // x0 = cantidad de datos leidos (esperamos 30)

    // -------------------------------------------------------
    // PASO 2: Inicializar acumuladores en cero
    // -------------------------------------------------------
    adr x1, suma_x
    str xzr, [x1]
    adr x1, suma_pond
    str xzr, [x1]
    adr x1, suma_pesos
    str xzr, [x1]

    // -------------------------------------------------------
    // PASO 3: Loop - calcular sumas
    // x10 = indice i (0..29)
    // x11 = peso Wi (1..30)
    // x9  = puntero base a datos[]
    // -------------------------------------------------------
    adr x9,  datos
    mov x10, #0
    mov x11, #1

loop_sumas:
    cmp x10, #30
    bge sumas_listas

    // Cargar datos[i]
    ldr x12, [x9, x10, lsl #3]

    // suma_x += Xi
    adr x13, suma_x
    ldr x14, [x13]
    add x14, x14, x12
    str x14, [x13]

    // suma_pond += Xi * Wi
    mul x15, x12, x11
    adr x13, suma_pond
    ldr x14, [x13]
    add x14, x14, x15
    str x14, [x13]

    // suma_pesos += Wi
    adr x13, suma_pesos
    ldr x14, [x13]
    add x14, x14, x11
    str x14, [x13]

    add x10, x10, #1
    add x11, x11, #1
    b   loop_sumas

sumas_listas:

    // -------------------------------------------------------
    // PASO 4: Calcular media ponderada
    // media = suma_pond / suma_pesos
    // -------------------------------------------------------
    adr x0, suma_pond
    ldr x0, [x0]
    adr x1, suma_pesos
    ldr x1, [x1]
    udiv x2, x0, x1

    adr x3, media_pond
    str x2, [x3]

    // -------------------------------------------------------
    // PASO 5: Abrir archivo de salida
    // -------------------------------------------------------
    mov x8,  SYS_OPENAT
    mov x0,  AT_FDCWD
    adr x1,  nombre_salida
    mov x2,  O_WRONLY | O_CREAT | O_TRUNC
    mov x3,  PERM_644
    svc #0

    // Guardar descriptor
    adr x4, fd_out
    str x0, [x4]
    mov x19, x0             // x19 = fd salida

    // -------------------------------------------------------
    // PASO 6: Escribir resultado en archivo y en pantalla
    // -------------------------------------------------------
    // Escribir en archivo (x19) y stdout (1) a la vez
    // usando subrutinas

    bl escribir_todo

    // Cerrar archivo
    mov x8,  SYS_CLOSE
    mov x0,  x19
    svc #0

    // -------------------------------------------------------
    // PASO 7: Salir
    // -------------------------------------------------------
    mov x8,  SYS_EXIT
    mov x0,  #0
    svc #0


// ============================================================
// SUBRUTINA: escribir_todo
// Escribe todas las lineas en archivo (x19) y stdout
// ============================================================
escribir_todo:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // --- MODULE=WEIGHTED_MEAN ---
    bl esc_module

    // --- TOTAL_VALUES=30 ---
    bl esc_total

    // --- SUM_X=<valor> ---
    bl esc_sumx

    // --- WEIGHT_SUM=<valor> ---
    bl esc_wsum

    // --- WEIGHTED_MEAN=<valor> ---
    bl esc_mean

    ldp x29, x30, [sp], #16
    ret

// ============================================================
// Escribe una linea en archivo y en stdout
// x19 = fd archivo, x1 = texto, x2 = longitud
// ============================================================
esc_linea_doble:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // Escribir en archivo
    mov x8,  SYS_WRITE
    mov x0,  x19
    svc #0

    // Escribir en stdout
    mov x8,  SYS_WRITE
    mov x0,  #1
    svc #0

    ldp x29, x30, [sp], #16
    ret

// ============================================================
esc_module:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x8, SYS_WRITE
    mov x0, x19
    adr x1, linea_module
    mov x2, linea_module_len
    svc #0
    mov x8, SYS_WRITE
    mov x0, #1
    adr x1, linea_module
    mov x2, linea_module_len
    svc #0
    ldp x29, x30, [sp], #16
    ret

// ============================================================
esc_total:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x8, SYS_WRITE
    mov x0, x19
    adr x1, linea_total
    mov x2, linea_total_len
    svc #0
    mov x8, SYS_WRITE
    mov x0, #1
    adr x1, linea_total
    mov x2, linea_total_len
    svc #0
    ldp x29, x30, [sp], #16
    ret

// ============================================================
esc_sumx:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // Etiqueta
    mov x8, SYS_WRITE
    mov x0, x19
    adr x1, etiq_sumx
    mov x2, etiq_sumx_len
    svc #0
    mov x8, SYS_WRITE
    mov x0, #1
    adr x1, etiq_sumx
    mov x2, etiq_sumx_len
    svc #0

    // Valor
    adr x0, suma_x
    ldr x0, [x0]
    adr x1, buf_num
    bl  int_a_ascii
    bl  esc_buf_num_doble

    // Newline
    bl  esc_newline_doble

    ldp x29, x30, [sp], #16
    ret

// ============================================================
esc_wsum:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    mov x8, SYS_WRITE
    mov x0, x19
    adr x1, etiq_wsum
    mov x2, etiq_wsum_len
    svc #0
    mov x8, SYS_WRITE
    mov x0, #1
    adr x1, etiq_wsum
    mov x2, etiq_wsum_len
    svc #0

    adr x0, suma_pesos
    ldr x0, [x0]
    adr x1, buf_num
    bl  int_a_ascii
    bl  esc_buf_num_doble
    bl  esc_newline_doble

    ldp x29, x30, [sp], #16
    ret

// ============================================================
esc_mean:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    mov x8, SYS_WRITE
    mov x0, x19
    adr x1, etiq_mean
    mov x2, etiq_mean_len
    svc #0
    mov x8, SYS_WRITE
    mov x0, #1
    adr x1, etiq_mean
    mov x2, etiq_mean_len
    svc #0

    adr x0, media_pond
    ldr x0, [x0]
    adr x1, buf_num
    bl  int_a_ascii
    bl  esc_buf_num_doble
    bl  esc_newline_doble

    ldp x29, x30, [sp], #16
    ret

// ============================================================
// Escribe buf_num en archivo y stdout
// Calcula longitud del string primero
// ============================================================
esc_buf_num_doble:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // Calcular longitud de buf_num
    adr x4, buf_num
    mov x5, #0
strlen_loop:
    ldrb w6, [x4, x5]
    cbz w6, strlen_fin
    add x5, x5, #1
    b   strlen_loop
strlen_fin:

    // Escribir en archivo
    mov x8, SYS_WRITE
    mov x0, x19
    adr x1, buf_num
    mov x2, x5
    svc #0

    // Escribir en stdout
    mov x8, SYS_WRITE
    mov x0, #1
    adr x1, buf_num
    mov x2, x5
    svc #0

    ldp x29, x30, [sp], #16
    ret

// ============================================================
esc_newline_doble:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    mov x8, SYS_WRITE
    mov x0, x19
    adr x1, newline
    mov x2, #1
    svc #0

    mov x8, SYS_WRITE
    mov x0, #1
    adr x1, newline
    mov x2, #1
    svc #0

    ldp x29, x30, [sp], #16
    ret

// ---- Fin modulo_1_media.s ---------------------------------
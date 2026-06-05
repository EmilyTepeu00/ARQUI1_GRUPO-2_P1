# ============================================================
# Makefile - Modulos ARM64 Invernadero Inteligente IoT
# ============================================================
# Uso en Raspberry Pi:
#   make          -> compila todos los modulos
#   make run      -> compila y ejecuta todos
#   make clean    -> elimina binarios y .o generados
#
# Uso en PC (cross-compiler):
#   Cambiar AS y LD por las lineas comentadas abajo
# ============================================================

# En Raspberry Pi (nativo):
AS = as
LD = ld

# En PC con cross-compiler, comentar las dos de arriba y usar estas:
# AS = aarch64-linux-gnu-as
# LD = aarch64-linux-gnu-ld

UTILS_OBJ = utils.o

MODULOS = modulo_1_media modulo_2_varianza modulo_3_anomalias modulo_4_prediccion modulo_5_tendecia

.PHONY: all run clean

all: $(UTILS_OBJ) $(MODULOS)

$(UTILS_OBJ): utils.s
	$(AS) utils.s -o utils.o

modulo_1_media: modulo_1_media.s $(UTILS_OBJ)
	$(AS) modulo_1_media.s -o modulo_1_media.o
	$(LD) utils.o modulo_1_media.o -o modulo_1_media

modulo_2_varianza: modulo_2_varianza.s $(UTILS_OBJ)
	$(AS) modulo_2_varianza.s -o modulo_2_varianza.o
	$(LD) utils.o modulo_2_varianza.o -o modulo_2_varianza

modulo_3_anomalias: modulo_3_anomalias.s $(UTILS_OBJ)
	$(AS) modulo_3_anomalias.s -o modulo_3_anomalias.o
	$(LD) utils.o modulo_3_anomalias.o -o modulo_3_anomalias

modulo_4_prediccion: modulo_4_prediccion.s $(UTILS_OBJ)
	$(AS) modulo_4_prediccion.s -o modulo_4_prediccion.o
	$(LD) utils.o modulo_4_prediccion.o -o modulo_4_prediccion

modulo_5_tendecia: modulo_5_tendecia.s $(UTILS_OBJ)
	$(AS) modulo_5_tendecia.s -o modulo_5_tendecia.o
	$(LD) utils.o modulo_5_tendecia.o -o modulo_5_tendecia

run: all
	@echo "--- Ejecutando modulos ARM64 ---"
	./modulo_1_media     && cat resultado_media.txt
	./modulo_2_varianza  && cat resultado_varianza.txt
	./modulo_3_anomalias && cat resultado_anomalias.txt
	./modulo_4_prediccion && cat resultado_prediccion.txt
	./modulo_5_tendecia  && cat resultado_tendencia.txt

clean:
	rm -f $(UTILS_OBJ)
	rm -f modulo_1_media.o modulo_2_varianza.o modulo_3_anomalias.o modulo_4_prediccion.o modulo_5_tendecia.o
	rm -f modulo_1_media modulo_2_varianza modulo_3_anomalias modulo_4_prediccion modulo_5_tendecia
	rm -f resultado_media.txt resultado_varianza.txt resultado_anomalias.txt resultado_prediccion.txt resultado_tendencia.txt

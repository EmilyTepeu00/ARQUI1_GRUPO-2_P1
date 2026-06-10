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
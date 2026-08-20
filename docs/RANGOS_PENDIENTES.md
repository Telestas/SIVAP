# Rangos de plausibilidad — pendientes de validación clínica

**Para el intensivista del equipo.** Este documento se rellena y se devuelve; a
partir de él se activan los avisos en la app.

## Qué se pide

La app avisa cuando un valor cae fuera de rango, **pero nunca bloquea la
captura** (CLAUDE.md §14): en UCI un valor extremo puede ser perfectamente real,
y bloquear un dato verdadero corrompe el dataset más que admitir un tecleo
erróneo, que la auditoría permite corregir.

Lo que hace falta es, para cada campo, el par de valores fuera de los cuales
tiene sentido preguntar «¿seguro?». **No** el rango normal del paciente: el
rango más allá del cual el valor es sospechoso de error de tecleo.

## Por qué están vacíos ahora mismo

La versión anterior del sistema traía rangos de paciente general ambulatorio
—FC 40–140, temperatura 35–37,5 °C, SpO₂ 92–100 %—. Un paciente ventilado en
cuidados intensivos los excede con normalidad. Activados así, el equipo vería
avisos en casi cada registro, aprendería a ignorarlos, y entonces tampoco vería
los verdaderos. Un aviso que siempre salta es peor que ningún aviso.

Por eso van todos vacíos hasta que alguien que trate pacientes ventilados los
fije. Hay una prueba automática que falla si alguien los rellena sin pasar por
aquí.

## Los campos

| Evento | Campo | Unidad | Mínimo | Máximo | Notas |
|---|---|---|---|---|---|
| Fase 1 · Estratificación | FiO₂ | % | | | |
| Fase 1 · Estratificación | PEEP | cmH₂O | | | |
| Fase 3 · Evaluación diaria | Duración de la detención de sedación | h | | | |
| Fase 3 · PVE (inicio) | Frecuencia respiratoria | rpm | | | |
| Fase 3 · PVE (inicio) | Vt | ml | | | |
| Fase 3 · PVE (inicio) | VM | L | | | |
| Fase 3 · PVE (inicio) | Pplateau | cmH₂O | | | |
| Fase 3 · PVE (inicio) | Driving pressure | cmH₂O | | | |
| Fase 3 · PVE (final) | Frecuencia respiratoria | rpm | | | |
| Fase 3 · PVE (final) | Vt | ml | | | |
| Fase 3 · PVE (final) | VM | L | | | |
| Fase 3 · PVE (final) | Pplateau | cmH₂O | | | |
| Fase 3 · PVE (final) | Driving pressure | cmH₂O | | | |
| Extubación | Tiempo entre PVE exitosa y extubación | h | | | |
| Extubación | Duración total de VMI | días | | | |
| Egreso de UCI | Duración de la estancia en UCI | días | | | |

El RSBI no aparece porque el Anexo 4 lo recoge por categorías (> 105 · ≤ 105 ·
≤ 58), no como número. Ver la observación de abajo.

## Dos cosas que conviene decidir a la vez

**1. El RSBI se está guardando como categoría, no como número.**
Es lo que dice el Anexo 4 y así está implementado. Pero un índice de Tobin de 92
y uno de 104 caen los dos en «≤ 105» y el dataset ya no los distingue. Si el
bioestadista quiere comparar el RSBI entre ramas, o buscar un punto de corte
distinto del que se fijó de antemano, va a necesitar el número.

Recoger el número y calcular la categoría cuesta lo mismo y no se pierde nada.
Al revés no tiene vuelta: **el dato que no se recogió no se puede recuperar
después.** Merece una conversación con quien vaya a analizar.

**2. Faltan unidades en dos campos.**
El Anexo 4 dice «Detención diaria de sedación: Sí/No + duración (horas o
minutos)» y «Tiempo entre PVE exitosa y extubación: horas / minutos». Ahora
mismo ambos se capturan en **horas con un decimal**. Si el equipo prefiere
minutos, se cambia — pero hay que fijarlo antes del primer paciente, porque
mezclar unidades en la misma columna es un error que no se detecta al mirar los
datos.

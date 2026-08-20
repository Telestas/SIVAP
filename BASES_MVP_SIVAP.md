# Bases del MVP — Sistema de captura del ensayo LIVERE

> **Revisión del 20 ago 2026.** Reescrito contra las fuentes reales: protocolo
> LIVERE 2026, proyecto de investigación y Anexo 4 (formulario de recolección).
> Sustituye la versión anterior, que asumía un estudio de cohorte con visitas en
> días 1, 3, 5, 10 y 14. Ese modelo era una suposición y era incorrecto.

> **Repositorio público.** Este documento describe el diseño metodológico, no a las
> personas. Sin nombres de investigadores ni de centros: esa información vive en el
> expediente del estudio.

---

## 1. Contexto

Equipo de médicos investigadores de medicina intensiva, en tres centros de La Habana,
ejecutando un ensayo clínico sin financiamiento dedicado, sin bioestadista ni
desarrollador en plantilla.

**Estudio**: LIVERE (LIberación segura de la VEntilación mecánica en entornos de
REcursos limitados). Ensayo clínico controlado, aleatorizado, multicéntrico,
prospectivo y longitudinal. Compara la aplicación del protocolo LIVERE frente al
manejo convencional en la liberación de la ventilación mecánica invasiva.

**Desenlace principal**: extubación fallida (reintubación en ≤72 h).

**Qué resuelve el software**: automatizar el proceso desde la asignación aleatoria
del paciente hasta la recolección estructurada de datos a lo largo de todo el proceso
de liberación y sus 28 días de seguimiento post-egreso, operando sin conexión y
consolidando un dataset exportable para análisis estadístico.

**Qué NO resuelve**: la validez metodológica del estudio. El cálculo de tamaño
muestral, la aprobación ética y el descegamiento final ocurren fuera del sistema.

---

## 2. Alcance del MVP

**Entra**

- Registro de investigadores con rol e institución.
- Enrolamiento: verificación de elegibilidad, captura de consentimiento informado,
  asignación de rama por secuencia pre-generada.
- Captura de datos por evento clínico (§5), con formularios definidos como datos.
- Trabajo 100 % offline, sincronización posterior.
- Auditoría de correcciones (valor anterior, autor, fecha, motivo).
- Exportación a `.xlsx`: dataset clínico y ficha de identidad en archivos separados,
  con la rama como A/B.

**No entra en el MVP** (evaluar para fase posterior)

- Corriente cualitativa: encuestas Likert al personal, entrevistas semiestructuradas,
  checklist de adherencia con auditoría interna. Decisión pendiente (CLAUDE.md §6 de
  pendientes).
- Dashboards de seguimiento en tiempo real.
- Notificaciones automáticas.
- Análisis estadístico dentro de la app. Se hace fuera, con el `.xlsx`.
- Soporte para otros estudios del grupo.

---

## 3. Arquitectura

| Componente | Tecnología | Justificación |
|---|---|---|
| App móvil + web | Flutter | Un solo código base, multiplataforma |
| Almacenamiento local | SQLite + SQLCipher | Persistencia cifrada, offline real |
| Backend | FastAPI | Ligero de mantener sin equipo dedicado |
| Base central | PostgreSQL | Consolidación multicéntrica |
| Sync | Cola local con timestamp, "último gana" + auditoría | Volumen del estudio no requiere más |
| Exportación | openpyxl | `.xlsx` desde datos consolidados |
| Cifrado | En reposo y en tránsito (TLS) | Datos de salud |

**Dimensionamiento**: tres centros, equipo de al menos nueve investigadores
declarados en el proyecto, más personal de UCI de cada centro. Revisar el supuesto de
concurrencia antes de fijar la estrategia de sync definitiva.

---

## 4. Roles y separación de funciones

El diseño de LIVERE exige separar cuatro funciones por razones metodológicas, no de
permisos. Quien selecciona pacientes debe estar cegado a la secuencia; quien evalúa
desenlaces, cegado a la rama.

| Rol | Qué hace | Qué ve | Cegado a |
|---|---|---|---|
| **Reclutador** | Verifica elegibilidad, registra consentimiento, enrola | Criterios de inclusión/exclusión, ficha, resultado de la asignación una vez consumida | La secuencia y qué rama viene después |
| **Aplicador** | Ejecuta el protocolo asignado y captura los eventos clínicos | Protocolo A o B, formularios de fase de sus pacientes | Cuál rama corresponde a LIVERE |
| **Evaluador de desenlaces** | Registra reintubación, eventos adversos, egreso, mortalidad | Datos clínicos del paciente | La rama asignada |
| **Investigador principal** | Administra el estudio, gestiona usuarios, exporta | Todo el sistema, en A/B | Nadie: es el único no cegado, y aun así el sistema no almacena la correspondencia |

**Observador** (opcional): solo lectura de la cohorte completa en A/B. Útil para
monitoreo institucional y auditoría externa.

**Reglas transversales**

- El aplicador no edita un registro ya enviado. Toda corrección la realiza el
  investigador principal, y siempre con entrada de auditoría y motivo.
- Ningún rol puede consultar qué rama viene a continuación en la secuencia.
- Ningún rol accede a la correspondencia A/B → LIVERE/control: no está en el sistema.

Además del analista, que consulta y exporta el dataset completo sin identidad y
sin capturar nada.

> **Pendiente de decisión**: si un mismo médico puede acumular roles (frecuente en
> equipos pequeños). Está implementado como configuración del estudio, no como
> regla del código, y el sistema identifica la combinación que rompe el
> cegamiento del desenlace principal: aplicador + evaluador en la misma persona.
> Corresponde a la investigadora principal, no al desarrollo.

---

## 5. Modelo de captura: eventos clínicos

**No hay visitas en días fijos.** La recolección sigue la trayectoria del paciente por
el proceso de liberación. Algunos eventos se repiten un número indeterminado de veces.

| Evento | Cuándo | Repetible | Notas |
|---|---|---|---|
| Enrolamiento | Al cumplir criterios de inclusión | No | Módulo 1 del Anexo 4 |
| Fase 1 — Estratificación de riesgo | Primeras 24 h de VMI | No | Todos los pacientes ventilados la completan |
| Fase 2 — Cribado | Desde 24–48 h | **Sí, diariamente** | Se repite hasta cumplir criterios o hasta que el paciente salga del proceso |
| Fase 3 — Evaluación diaria | Tras superar el cribado | **Sí, diariamente** | Detención de sedación, evaluación de ventilación espontánea |
| Fase 3 — PVE | Al concluir evaluación diaria con éxito | **Sí, 1 a 4+ intentos** | Cada intento registra monitorización al inicio y al final |
| Traqueostomía | Si procede | No | Cambia la trayectoria del paciente |
| Extubación | Tras PVE exitosa | No | Módulo 3 del Anexo 4 |
| Soporte post-extubación | Inmediato a la extubación | No | HFNC / VNI / ambos |
| Reintubación | ≤72 h post-extubación | No | **Desenlace principal** |
| Egreso de UCI | Al alta de la unidad | No | Estado vivo/fallecido |
| Seguimiento post-egreso | Hasta 28 días | No | Mortalidad a 7, 14, 28 días |

**Implicación de modelado**: un evento necesita tipo, número de ocurrencia (para los
repetibles), fecha real de ocurrencia (no programada) y estado. Un índice entero de
"día de visita" no puede representar esto.

**Implicación de interfaz**: la pantalla del paciente es una línea de tiempo por
fases con eventos acumulables, no un juego de pestañas fijas.

**Trayectorias incompletas**: un paciente puede salir del proceso en cualquier fase
—traqueostomía, fallecimiento, traslado—. El modelo admite esas trayectorias sin
marcarlas como error: un evento que no ocurrió simplemente no existe.

---

## 6. Campos del formulario (Anexo 4)

Fuente: `Anexo 4 — Formulario de Recolección de Datos Clínicos, Ensayo LIVERE`.
Estos son los campos reales; sustituyen íntegramente a los de demostración.

### Módulo 1 — Datos generales del paciente

| Campo | Tipo | Categorías / notas |
|---|---|---|
| Código del paciente | Autogenerado | Correlativo, es el identificador del estudio |
| Teléfonos de contacto | Texto | Hasta dos |
| Protocolo aplicado | Asignado | **A** o **B** — nunca elegido por el investigador |
| Institución | Selección única | Multicéntrico (CLAUDE.md restricción 8) |
| Edad | Número | Años |
| Sexo | Selección única | Masculino / Femenino |
| IMC | Selección única | <18,5 (BP) · 18,5–24,9 (NP) · 25–29,9 (SP) · 30–39,9 (Obeso) · >40 (Superobeso) |
| Fecha de ingreso a UCI | Fecha | |
| Causa de intubación y VMI | Selección única | Respiratoria · Neurológica · Cardiovascular · Metabólica · Anestésica/quirúrgica · Paro cardiorrespiratorio · Shock |
| Comorbilidades relevantes | Selección múltiple | HTA · DM · CI · IC · ERC · EPOC · AB · ECV previa |

### Módulo 2 — Datos ventilatorios

| Campo | Tipo | Categorías / notas |
|---|---|---|
| Fecha de inicio de VMI | Fecha | |
| Fecha de primera evaluación (Fase 1) | Fecha | |
| FiO₂ en primera evaluación | Número | |
| PEEP en primera evaluación | Número | cmH₂O |
| Fecha de cumplimiento de criterios de cribado (Fase 2) | Fecha | |
| Detención diaria de sedación | Sí/No + duración | Horas o minutos |
| Evaluación diaria de ventilación espontánea | Sí/No + duración | >15 min · 10–15 min · <10 min |
| Fecha de primera PVE | Fecha | |
| Método de PVE empleado | Selección única | Tubo en T · PSV · PSV+PEEP · CPAP |
| **Monitorización al inicio de la PVE** | Grupo | RSBI (>105 · ≤105 · ≤58), frecuencia respiratoria, Vt (ml), VM (L), Pplateau (cmH₂O), driving pressure (cmH₂O) |
| **Monitorización al final de la PVE** | Grupo | Mismos campos que al inicio |
| Resultado de PVE | Selección única | Éxito · Fallo |
| Duración de la PVE | Selección única | <30 min · 30–60 min · 60–120 min |
| Total de PVE intentadas | Selección única | 1 · 2 · 3 · 4 o más |
| ¿Traqueostomía? | Sí/No + fecha | |

> El bloque de PVE se repite por intento (§5). El campo "total de PVE intentadas" del
> Anexo 4 es derivable del número de eventos registrados; conviene calcularlo, no
> pedirlo dos veces.

### Módulo 3 — Evaluación para extubación

| Campo | Tipo | Categorías / notas |
|---|---|---|
| Fecha de PVE exitosa | Fecha | |
| Fecha de extubación | Fecha | |
| ¿Test de fuga? | Sí/No | |
| Resultado del test de fuga | Selección única | Con fuga · Sin fuga |
| Tiempo entre PVE exitosa y extubación | Duración | Horas / minutos |
| Duración total de VMI | Número | Días |

### Módulo 4 — Desenlaces clínicos

| Campo | Tipo | Categorías / notas |
|---|---|---|
| ¿Soporte post-extubación? | Sí/No | |
| Tipo de soporte | Selección única | HFNC · VNI · VNI+HFNC |
| **¿Reintubación en ≤72 h?** | Sí/No | **Desenlace principal** |
| Causa de reintubación | Selección única | Inestabilidad hemodinámica · Laringoespasmo · Broncoaspiración · Estridor · Fallo respiratorio agudo · Deterioro neurológico · Otra |
| Eventos adversos post-extubación | Selección múltiple | Ninguna · Laringoespasmo · Broncoaspiración · Estridor · Fallo respiratorio agudo |
| Duración de estancia en UCI | Número | Días |
| Estado al egreso de UCI | Selección única | Vivo · Fallecido |
| Fallecimiento posterior al egreso | Selección única | Primeros 7 días · 8–14 días · 15–28 días · No fallecimiento a 28 días |

### Variables derivadas (no se capturan, se calculan)

Definidas en la matriz de operacionalización del proyecto: días libres de VMI, días
libres de UCI, tiempo de traqueostomía 1 (intubación → traqueostomía), tiempo de
traqueostomía 2 (traqueostomía → separación/decanulación), tipo de destete (simple ·
dificultoso · prolongado), reingreso en UCI ≤72 h.

> **Pendiente**: la sección "Información general para llenado del formulario" del
> Anexo 4 está vacía en el documento recibido. Si existe, define validaciones.

---

## 7. Elegibilidad

**Inclusión**
- Adultos (>18 años) en VMI. **Umbral en disputa**: el protocolo dice >24 h, el
  proyecto >48 h. Resolver antes de programar el filtro.
- Estabilidad hemodinámica y parámetros compatibles con inicio de liberación.
- Consentimiento libre e informado firmado.

**Exclusión**
- Trastornos neuromusculares graves
- Contraindicaciones para aplicar el protocolo
- Decisión de cuidados paliativos · estadio terminal · orden de no reanimación
- Glasgow ≤8 puntos
- Negativa del paciente o su representante
- Imposibilidad de seguimiento por traslado
- Participación simultánea en otro ensayo que interfiera con los desenlaces

**Muestra**: consecutiva. **Sin cálculo formal de tamaño muestral** — pendiente del
bioestadista (CLAUDE.md, pendientes §2).

---

## 8. Asignación de rama

Aleatorización **simple**, individual, sin bloques ni estratos. Secuencia generada por
computadora antes del primer enrolamiento, consumida en orden. Semilla custodiada
fuera del sistema (CLAUDE.md restricción 7).

La implementación actual (`allocation_strategy.dart`) cumple con esto y es
verificable: SplitMix32 con algoritmo fijado en el propio código, vectores de prueba,
y regeneración desde semilla para auditoría externa. **Se conserva.** Lo único que
cambia es el nombre de las ramas: `nuevo/vigente` → `A/B`.

> El proyecto describe sobres físicos sellados y numerados. Decidir si la app los
> reemplaza o coexisten (CLAUDE.md, pendientes §10).
>
> **Y hay una razón técnica para decidirlo pronto.** El contador de la secuencia
> vive en cada dispositivo: dos trabajando sin conexión asignan ambos la misma
> posición, y al sincronizar el reparto deja de ser el que la secuencia dictaba,
> sin que nada lo detecte. La salida es repartir rangos disjuntos de la
> secuencia por centro o dispositivo — que es exactamente lo que hacen los
> sobres numerados, y por eso son la misma decisión.

**Nota sobre aleatorización simple**: no equilibra las ramas por construcción. Con 60
pacientes es normal terminar 33/27. Si el desequilibrio importa, la decisión es pasar
a bloques, y eso es otra implementación de `AllocationStrategy`, no un parche.

---

## 9. Consentimiento informado

Existe en el Anexo 3 del proyecto, en dos documentos: información general y
consentimiento propiamente dicho. Se captura en el sistema con versión del documento,
fecha y firma.

El sistema no admite enrolamiento real hasta el flag de aprobación del CEI de cada
institución participante.

---

## 10. Exportación

Dos archivos separados:

1. **Dataset clínico**: código de paciente, institución, rama (A/B), todos los eventos
   y sus valores. Sin identidad. Es el que recibe el bioestadista.
2. **Ficha de identidad**: código de paciente ↔ teléfonos de contacto. Acceso
   restringido al investigador principal.

El dataset clínico **nunca** sale desciegado. La correspondencia A/B se aplica fuera
del sistema, una vez, al cierre del estudio.

Formato tabular apto para análisis en SPSS o R: una fila por evento (formato largo),
con las variables derivadas calculadas.

---

## 11. Condición de fallo

Este diseño asume:

- Que la aleatorización final será **simple**. Si el bioestadista pide bloques o
  estratificación por centro (razonable en multicéntrico), el módulo de asignación
  debe ajustarse antes de enrolar.
- Que el cegamiento es de **seleccionadores, evaluadores y analistas**. Si el CEI o el
  bioestadista exigen el "triple ciego" que menciona el resumen del proyecto, hay que
  revisar qué ve el aplicador.
- Que los eventos del §5 cubren la trayectoria completa. Si la práctica revela hitos
  no contemplados, el modelo de eventos los admite sin refactor — esa es la razón de
  no usar un índice de día.
- Que el CEI aprobará en un plazo razonable. El sistema puede construirse en paralelo,
  pero no enrolar.

---

## 12. Próximos pasos

Ver `docs/REENCAMINAMIENTO.md` para el plan de corrección ordenado por riesgo.
Resumen: visibilidad del repositorio → cegamiento → modelo por eventos → campos
reales → ficha mínima e institución → roles. Todo ello **antes** del backend.

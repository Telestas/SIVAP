# SIVAP — Bases del MVP
## Sistema de Validación de Protocolo (Estudio de Cohorte)

> Nombre de trabajo: **SIVAP** (Sistema de Validación de Protocolos). Provisional — cambiar aquí y en CLAUDE.md si se elige otro.

---

## 1. Contexto y propósito

Equipo de médicos investigadores de un hospital cubano, ejecutando una investigación de iniciativa del propio servicio, sin acceso a bioestadista, informático o desarrollador dedicado.

**Objetivo del estudio**: validar un protocolo clínico nuevo frente al protocolo vigente ("viejo"), mediante un estudio de cohorte, con recolección de datos en visitas fijas: Día 1, 3, 5, 10, 14 (índices ajustables si el estudio lo requiere, ver sección 5).

**Objetivo del software**: automatizar el proceso desde el enrolamiento del paciente hasta la recolección estructurada de datos, funcionando en condiciones de conectividad inestable, y consolidando todo en un dataset exportable para análisis estadístico.

---

## 2. Alcance del MVP (lo que SÍ entra en la primera versión)

- Registro de investigadores con roles (ver sección 4).
- Enrolamiento de paciente: ficha de identidad + datos de contacto.
- Asignación de protocolo (viejo/nuevo) mediante **aleatorización simple pre-generada**, cargada como lista consumible por el sistema (ver sección 6 — módulo desacoplado, pendiente de confirmación del bioestadista).
- Captura de consentimiento informado dentro del sistema (firma digital, fecha, versión del documento — ver sección 7).
- Formularios de visita (Día 1, 3, 5, 10, 14) según **definición configurable de campos** (ver sección 5) — no hardcodeados, porque el equipo indicó que el formulario podría ajustarse durante el estudio.
- Trabajo 100% offline en la app móvil, con sincronización a la nube cuando haya conexión.
- Exportación del dataset consolidado a Excel (.xlsx), en formato apto para análisis estadístico posterior.
- Registro de auditoría (audit trail): ninguna visita ya enviada se edita directamente; toda corrección queda con valor original, autor, fecha y motivo.

## 2.1 Fuera de alcance del MVP (fase posterior)

- Dashboards de seguimiento en tiempo real.
- Soporte multi-estudio (esto se piensa para una única investigación por ahora; si el equipo hace varias investigaciones a la vez, se evalúa después).
- Notificaciones automáticas de visitas próximas/vencidas.
- Reportes estadísticos dentro de la propia app (el análisis se hace fuera, con el Excel exportado).

---

## 3. Arquitectura propuesta

| Componente | Tecnología | Justificación |
|---|---|---|
| App móvil + web | Flutter | Un solo código base, cliente pidió multiplataforma |
| Almacenamiento local (offline) | Drift o Isar (SQLite embebido) | Persistencia local robusta, consultas estructuradas |
| Backend | FastAPI | Ligero, rápido de mantener sin equipo dedicado |
| Base de datos central | PostgreSQL | Consolidación de todos los investigadores/pacientes |
| Sync | Cola local con timestamp + resolución "último gana" + log de auditoría | Volumen de 4–10 investigadores no requiere algo más complejo |
| Exportación | openpyxl (backend) | Generación de .xlsx desde los datos consolidados |
| Cifrado | En reposo (dispositivo y servidor) y en tránsito (TLS) | Datos de salud identificables (nombre + contacto) |

---

## 4. Roles de usuario

| Rol | Ficha del paciente | Registros de visita | Usuarios/dataset |
|---|---|---|---|
| **Observador** | Solo lectura | Solo lectura | Ve todo, no modifica nada |
| **Recolector de campo** | Crea pacientes nuevos (enrolamiento) | Crea y registra visitas de sus pacientes. No edita una visita ya enviada ni la ficha tras creada | No gestiona usuarios |
| **Administrador / Investigador principal** | Crear, editar (con historial), eliminar | Crear, editar (con historial), eliminar cualquier visita | Gestiona usuarios, ve todo el dataset, exporta a Excel |

**Regla no negociable**: ninguna edición sobre un dato ya enviado ocurre "en silencio". Toda corrección genera una entrada de auditoría (valor anterior, valor nuevo, autor, fecha/hora, motivo).

---

## 5. Formularios de visita — PENDIENTE DE CONFIRMACIÓN

> Esta sección queda como **plantilla de ejemplo**. Reemplazar con el listado real de variables por visita en cuanto el equipo lo comparta (Word, PDF, foto de planilla, o texto directo).

Ejemplo de estructura esperada por visita:

| Campo | Tipo de dato | Obligatorio | Rango/validación |
|---|---|---|---|
| Fecha de la visita | Fecha | Sí | No anterior al enrolamiento |
| Signos vitales (TA, FC, FR, Temp) | Numérico | Sí | Rangos clínicos por definir |
| Síntomas presentes | Selección múltiple | Sí | Catálogo por definir |
| Valores de laboratorio | Numérico | Depende de la visita | Por definir |
| Observaciones del investigador | Texto libre | No | — |

Cada campo se define como un registro configurable (nombre, tipo, obligatoriedad, validación) para que un ajuste de protocolo no requiera recompilar la app — solo actualizar la definición en el backend.

---

## 6. Módulo de asignación de protocolo (aleatorización)

**Estado**: pendiente de definición por el bioestadista del equipo.

El MVP implementa por defecto: **aleatorización simple pre-generada** (lista de secuencia cargada al sistema, consumida en orden por cada nuevo paciente elegible). Esta pieza se construye **desacoplada** del resto del sistema, de modo que si más adelante se decide que la asignación depende de criterios clínicos (edad, diagnóstico, gravedad), se reemplaza el módulo sin rediseñar el resto de la aplicación.

**No implementado y explícitamente descartado para el MVP**: que el investigador elija manualmente el protocolo al crear el paciente sin una regla objetiva detrás — esto introduce sesgo de selección y compromete la validez del estudio como ensayo aleatorizado.

---

## 7. Consentimiento informado

Estado actual: existe borrador, pendiente de aprobación por el Comité de Ética de la Investigación (CEI).

El sistema no puede usarse para reclutar pacientes reales hasta que el CEI apruebe protocolo y consentimiento. El MVP incluye una pantalla de captura de consentimiento (firma digital, fecha, versión del documento aprobado) para trazabilidad, activable una vez exista la aprobación formal.

---

## 8. Datos personales y separación ficha/clínica

Dado que se manejará nombre y contacto completos del paciente:

- La **ficha de identidad** (nombre, contacto) se almacena separada de los **datos clínicos del estudio**, vinculadas solo por un ID interno.
- Esto permite exportar el dataset clínico para análisis (bioestadista, publicación) sin exponer identidad, sin rediseñar nada.
- Cifrado obligatorio de la base local (dispositivo) y en el servidor.

---

## 9. Condición de fallo

Este diseño asume:
- Que la aleatorización final será simple (no por bloques ni estratificada) — si el bioestadista pide estratificación, el módulo de asignación (sección 6) debe ajustarse antes de enrolar pacientes.
- Que 4–10 investigadores en paralelo es el volumen real — un crecimiento significativo del equipo requeriría revisar la estrategia de sync.
- Que el CEI aprobará el consentimiento en un plazo razonable — el sistema puede construirse en paralelo, pero no reclutar pacientes reales hasta esa aprobación.

---

## 10. Próximos pasos

1. Confirmar campos exactos por visita (sección 5).
2. Confirmar con bioestadista el método de aleatorización (sección 6).
3. Definir nombre final del proyecto.
4. Generar `CLAUDE.md` (constitución del repositorio) y prompts secuenciados por hito para Claude Code.


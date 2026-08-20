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
- Asignación de protocolo (viejo/nuevo) mediante **aleatorización simple generada por computadora** desde una semilla registrada, consumida en orden (ver sección 6 — módulo desacoplado).
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
| Almacenamiento local (offline) | SQLite + SQLCipher, SQL escrito a mano | Persistencia cifrada en reposo, con esquema legible sin generadores de código (decidido 20 ago 2026, en vez de Drift o Isar) |
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

**Estado**: **decidido por el equipo (20 ago 2026)**.

El sistema implementa **aleatorización simple generada por computadora**. Cómo funciona, en concreto:

1. Antes de enrolar al primer paciente, el investigador principal fija una **semilla** (un número) y una **longitud** de secuencia holgada frente al tamaño previsto de la cohorte.
2. El sistema genera de una vez la secuencia completa: un **código binario** donde `0` = protocolo vigente (rama control) y `1` = protocolo nuevo. Cada posición se sortea de forma independiente.
3. Cada paciente enrolado consume la siguiente posición, en orden estricto. El investigador no ve qué rama toca antes de enrolar, y no puede modificarla.
4. La semilla, la longitud y el código binario quedan **en el acta del estudio**.

### Cómo verificar la aleatorización sin fiarse de la app

El generador no es el del lenguaje de programación, sino uno fijado en el
código del proyecto (**splitmix32**), precisamente para que la secuencia no
dependa de qué versión de qué herramienta se usó. Cualquiera puede
reimplementarlo y comprobar el resultado. La especificación completa, sobre
enteros de 32 bits sin signo:

```
estado = semilla
repetir para cada asignación:
    estado = (estado + 0x9E3779B9) mod 2^32
    z = estado
    z = ((z XOR (z >>> 16)) * 0x21F0AAAD) mod 2^32
    z = ((z XOR (z >>> 15)) * 0x735A2D97) mod 2^32
    z = z XOR (z >>> 15)
    bit = z AND 1          # 1 = protocolo nuevo, 0 = protocolo vigente
```

Vectores de comprobación, para saber que la reimplementación es correcta:

| Semilla | Primeros bits |
|---|---|
| 12345 | `1101101100000100` (16) |
| 987 | `10111100101110101111001101000111` (32) |

Con eso, un revisor externo con Python o R regenera la secuencia del estudio
desde la semilla del acta y la compara contra las asignaciones registradas,
paciente a paciente, sin tener que confiar en el software.

Por qué la semilla: es lo que convierte el azar en algo verificable. Un revisor, un comité o el propio equipo pueden regenerar la secuencia con esa semilla y comprobar, paciente a paciente, que las asignaciones registradas son exactamente las que la secuencia dictaba. Sin semilla registrada, "fue aleatorio" es una afirmación que nadie puede comprobar.

Nota metodológica: la aleatorización simple **no garantiza un reparto 50/50**. Con 60 pacientes es normal terminar 33/27 o similar. Eso es correcto y esperado; forzar el equilibrio exacto dejaría de ser aleatorización simple. Si el desequilibrio llegara a preocupar al equipo, la alternativa es aleatorización por bloques.

Esta pieza se construye **desacoplada** del resto del sistema: si más adelante se decide pasar a bloques, a estratificación, o a una asignación que dependa de criterios clínicos (edad, diagnóstico, gravedad), se reemplaza el módulo sin rediseñar el resto de la aplicación.

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
- Que la aleatorización es simple (no por bloques ni estratificada), decidido por el equipo — si más adelante se pidiera estratificación, el módulo de asignación (sección 6) debe ajustarse **antes** de enrolar pacientes, nunca a mitad del estudio.
- Que la semilla de aleatorización se fija una vez y queda registrada. Cambiarla con pacientes ya enrolados invalida la trazabilidad de las asignaciones previas.
- Que 4–10 investigadores en paralelo es el volumen real — un crecimiento significativo del equipo requeriría revisar la estrategia de sync.
- Que el CEI aprobará el consentimiento en un plazo razonable — el sistema puede construirse en paralelo, pero no reclutar pacientes reales hasta esa aprobación.

---

## 10. Próximos pasos

1. Confirmar campos exactos por visita (sección 5).
2. ~~Confirmar el método de aleatorización~~ — **hecho** (sección 6). Queda fijar la semilla y la longitud de la secuencia del estudio real, y dejarlas en el acta.
3. Definir nombre final del proyecto.
4. Generar `CLAUDE.md` (constitución del repositorio) y prompts secuenciados por hito para Claude Code.


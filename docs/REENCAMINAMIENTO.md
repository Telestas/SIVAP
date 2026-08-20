# Reencaminamiento — 20 ago 2026

Plan de corrección de rumbo tras leer las fuentes reales del ensayo LIVERE
(protocolo, proyecto de investigación, Anexo 4).

**Estado: pasos 0 a 3 hechos. Pendientes 4, 5 y 6.**

## Por qué

Los Hitos 0–2 se construyeron contra unas bases que asumían un **estudio de cohorte
con visitas en días fijos (1, 3, 5, 10, 14)**. Las fuentes reales describen un
**ensayo clínico aleatorizado multicéntrico con captura por eventos clínicos y
cegamiento**.

El código no estaba mal escrito. Estaba bien construido sobre premisas equivocadas.
La mayor parte se conserva: la separación ficha/clínica, la auditoría, el mecanismo de
formularios configurables, la persistencia cifrada y el módulo de aleatorización
siguen siendo correctos y se mantienen.

**Regla de secuencia**: los pasos 4 a 6 se completan antes de escribir el backend.
Una vez exista esquema en PostgreSQL con datos sincronizados, cada uno pasa de
refactor a migración.

---

## ✅ Paso 0 — Visibilidad del repositorio · hecho

El `README.md` declaraba "repositorio privado" y el repositorio está **público**.

**Qué se hizo**: se optó por mantenerlo público y quitar de él todo lo identificable.
El README lo declara, y CLAUDE.md añade la restricción 15: sin nombres de
investigadores, sin nombres de centros, sin datos de pacientes, sin semillas reales.
Los datos de demostración quedan marcados como inventados.

Con el repositorio público, `docs/DISTRIBUCION.md` deja de estar bloqueado: Pages
funciona y las releases se descargan sin autenticación.

**Lo que queda dicho, por si el CEI lo pregunta**: el repositorio expone el diseño
metodológico completo de un ensayo pendiente de aprobación ética. Es una decisión
tomada a conciencia, no un descuido, y no hay en él ningún dato de paciente ni ninguna
persona identificada.

---

## ✅ Paso 1 — Documentos base · hecho

`CLAUDE.md` y `BASES_MVP_SIVAP.md` reescritos contra el protocolo, el proyecto y el
Anexo 4. `README.md` actualizado. El texto del consentimiento de demostración en
`seed_data.dart` ya no dice "estudio de cohorte" — y tampoco insinúa qué rama es cuál,
porque el documento que firma el paciente tampoco puede romper el cegamiento.

---

## ✅ Paso 2 — Cegamiento · hecho

Era el más urgente. `protocolo.dart` decía:

```dart
vigente('PROT. VIGENTE', 'PROTOCOLO VIGENTE', 'Rama control'),
nuevo('PROT. NUEVO', 'PROTOCOLO NUEVO', 'Rama experimental');
```

**Qué se hizo**

- `Protocolo` pasa a `a` / `b`, con etiquetas "PROT. A" / "PROT. B".
- Eliminado el campo `rama`, que filtraba justo lo que el cegamiento protege.
- Tokens de color renombrados: `nuevoBg`/`vigenteBg` → `ramaABg`/`ramaBBg`.
- Los recuentos del panel pasan a "A: n · B: m".
- El panel de asignación del enrolamiento muestra la letra y la hora, y dice
  explícitamente que el sistema no registra a qué protocolo corresponde cada rama.
- `test/cegamiento_test.dart` falla si alguna etiqueta de rama contiene "nuevo",
  "vigente", "control", "experimental", "LIVERE", "convencional", "intervención" o
  "placebo"; si el consentimiento o los datos de demostración los mencionan; o si la
  semilla deja de estar marcada como de demostración.

---

## ✅ Paso 3 — Modelo por eventos clínicos · hecho

`Visit` definía `int dia` (1, 3, 5, 10, 14) y `fechaProgramada`, más un estado
`perdida`. Todo eso asumía calendario fijo.

**Qué se hizo**

- `Visit` → `EventoClinico`, con `tipo`, `ocurrencia`, `fechaOcurrencia` (real, no
  programada), `estado` y `valores`.
- `TipoEvento`: los once hitos de BASES §5, cada uno con su fase, si es repetible y
  cómo se nombra cada ocurrencia ("intento 2", "día 3").
- `FaseEstudio`: siete fases, para agrupar la línea de tiempo.
- `VisitFormDefinition` → `EstudioFormDefinition`, con una `EventoDefinicion` por tipo
  de evento. `FieldDefinition.dias` desaparece: los campos pertenecen a su evento.
- Desaparece el estado "perdida". **Enrolar ya no pre-crea ningún calendario**: los
  registros se crean cuando el hito ocurre.
- La pantalla de captura se parte en dos: `PacienteTimelineScreen` (línea de tiempo
  por fases con eventos acumulables) y `EventoFormScreen` (captura de una ocurrencia).
- `DayPill` → `FasePill`.
- Esquema SQLite: `visitas`/`visita_valores` → `eventos`/`evento_valores`, con un
  índice parcial que impide dos borradores abiertos del mismo hito.
- Un hito no repetible ya registrado lanza `EventoNoRepetible`: se corrige, no se
  duplica.
- Tipos de campo nuevos: `siNo` y `fecha`, para que el paso 4 sea solo datos.

**Trayectorias incompletas**: hay pruebas de que un paciente con traqueostomía que
nunca llega a extubarse es una trayectoria válida, no un error.

---

## ⬜ Paso 4 — Campos reales del Anexo 4

El mecanismo ya está bien: `EstudioFormDefinition` es configurable como datos y la
pantalla la recorre sin nada escrito a mano. Lo que hay en `seed_data.dart` es un
**esqueleto provisional** trazable a BASES §6 —entre dos y siete campos por evento—,
suficiente para que la línea de tiempo funcione y se pueda enseñar.

**Acción**: sustituirlo por los cuatro módulos completos del Anexo 4, con sus
categorías exactas.

**Atención a los rangos**: van casi todos vacíos a propósito. Los que había (FC
40–140, temp 35–37,5, SpO₂ 92–100) eran de paciente general ambulatorio y un paciente
ventilado en UCI los excede con normalidad. Ponerlos sin validación de un intensivista
produciría avisos falsos que el equipo aprendería a ignorar, que es peor que no
tenerlos. Recordar la restricción 14: los rangos avisan, no bloquean.

---

## ⬜ Paso 5 — Ficha mínima e institución

`domain/models/patient.dart` sigue pidiendo nombre, carné de identidad, dirección,
teléfono y número de historia clínica. El Anexo 4 solo pide código autogenerado,
teléfonos e institución.

**Acción**

- **Añadir `institucion`** — obligatorio, el ensayo es multicéntrico y no está en el
  modelo. También en `EventoClinico` y en `Investigador`.
- **Quitar `carneIdentidad` y `direccion`** — no los pide el formulario del estudio.
  Cada dato personal almacenado es superficie de riesgo a justificar ante el CEI
  (restricción 9).
- Evaluar `nombre` y `numeroHistoriaClinica`: el Anexo 4 no los pide, pero el equipo
  necesita identificar al paciente en la sala. Si se conservan, con decisión explícita
  documentada, y siempre en la ficha, nunca en el dataset clínico.
- Decidir dónde viven edad y sexo: son variables del análisis (Módulo 1), no identidad.

---

## ⬜ Paso 6 — Roles según cegamiento

Los tres roles actuales (observador / recolector / administrador) no reflejan la
separación de funciones que exige el diseño del ensayo.

**Acción**: implementar la tabla de BASES §4 — reclutador, aplicador, evaluador de
desenlaces, investigador principal, más observador opcional. `role.dart` ya tiene la
forma correcta (permisos como propiedades del enum), así que el cambio es de
contenido, no de estructura.

**Antes de programarlo**: decidir con la investigadora principal si un mismo médico
puede acumular roles, frecuente en equipos pequeños, y si eso compromete el
cegamiento.

---

## Después

Retomar `docs/PENDIENTE.md`: backend FastAPI, sincronización, exportación `.xlsx`,
TLS. El inventario sigue siendo válido; solo cambia el modelo de datos sobre el que
opera.

---

## Lo que se conservó sin tocar

Para que quede explícito, porque es la mayor parte del trabajo hecho:

- `allocation_strategy.dart`, salvo el nombre de las ramas. SplitMix32 con algoritmo
  fijado en el propio código, vectores de verificación, regeneración desde semilla, y
  la decisión deliberada de no exponer la siguiente rama sin consumirla.
- La separación `Patient` / registro clínico.
- El mecanismo de auditoría, con disparadores que impiden modificar o borrar.
- La persistencia local cifrada (SQLite + SQLCipher, clave en Keystore/Keychain).
- El mecanismo de formularios como datos.
- La integración continua (`verificar.yml`, `apk.yml`, `pages.yml`).
- El sistema de diseño y las tipografías.

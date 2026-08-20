# Reencaminamiento — 20 ago 2026

Plan de corrección de rumbo tras leer las fuentes reales del ensayo LIVERE
(protocolo, proyecto de investigación, Anexo 4).

**Estado: los seis pasos hechos.** Quedan decisiones del equipo, no código;
están en `docs/PENDIENTE.md` y en CLAUDE.md.

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

## ✅ Paso 4 — Campos reales del Anexo 4 · hecho

El esqueleto provisional se sustituyó por los cuatro módulos del Anexo 4, con
sus categorías exactas: IMC en cinco tramos, siete causas de intubación, ocho
comorbilidades, cuatro métodos de PVE, RSBI en sus tres categorías, siete causas
de reintubación, cuatro tramos de mortalidad post-egreso.

**Qué NO se pide, y por qué**

- «Total de PVE intentadas» → se cuenta a partir del número de eventos de PVE
  registrados. El propio Anexo señala que es derivable, y pedir dos veces el
  mismo dato es pedir que discrepen. Hay una prueba que falla si alguien lo
  añade.
- Fechas de PVE y de traqueostomía → son la fecha del propio evento.
- Código, teléfonos, centro, edad, sexo y protocolo → están en la ficha.

**Qué SÍ se pide aunque parezca derivable** —duración total de VMI, fecha de PVE
exitosa, tiempo entre PVE y extubación—: si el evento de origen falta o se
registró mal, el dato derivado se perdería sin que nadie lo notara. Sirven
además de comprobación cruzada.

**Los rangos van vacíos**, y hay una prueba que falla si alguien los rellena sin
pasar por `docs/RANGOS_PENDIENTES.md`. Ese documento está listo para que el
intensivista lo complete, y recoge además dos decisiones que conviene tomar a la
vez: que el RSBI se está guardando como categoría y no como número, y que faltan
por fijar las unidades de dos duraciones.

---

## ✅ Paso 5 — Ficha mínima e institución · hecho

- **`Institucion` entra en el modelo**: en la ficha, en cada evento clínico y en
  cada investigador. En el evento y no solo en la ficha porque un paciente
  trasladado tendría eventos de más de un centro, y el análisis por centro
  necesita saber dónde ocurrió cada cosa.
- **Fuera el carné de identidad y la dirección.** No los pide el Anexo 4, y cada
  dato personal almacenado es superficie de riesgo a justificar (CLAUDE.md §9).
- **Entra el código de paciente**, con prefijo de centro y correlativo:
  `HC-004`. Es lo que se ve en pantalla y lo que sale en el dataset. La clave
  real sigue siendo un identificador aleatorio de 128 bits, que no choca entre
  dispositivos.
- **`nombre` y `numeroHistoriaClinica` se conservan** por decisión explícita: el
  equipo necesita identificar al paciente en la sala. Viven solo en la ficha y
  nunca salen en el dataset clínico. Es una excepción a justificar ante el CEI,
  y está anotada como tal.

Las pantallas pasan a mostrar el código en vez del nombre siempre que se puede.

---

## ✅ Paso 6 — Roles según cegamiento · hecho (con una decisión pendiente)

Los tres roles anteriores se sustituyeron por las funciones de BASES §4:
reclutador, aplicador, evaluador de desenlaces, analista, investigador principal
y observador.

Lo que hace que esto sea cegamiento y no una tabla de permisos:

- **La captura va por tipo de hito.** El aplicador registra las fases del
  protocolo; el evaluador, los desenlaces. Intentar lo contrario lanza
  `FueraDeSuFuncion`. Hay una prueba que comprueba que ningún hito se queda sin
  una función que lo capture: un hito que no captura nadie es un dato que no se
  recoge y nadie se entera hasta el análisis.
- **El evaluador de desenlaces no ve la rama.** La app le muestra «RAMA OCULTA»
  en lugar del distintivo A/B. Si la viera, su juicio sobre si hubo extubación
  fallida —el desenlace principal— dejaría de ser independiente.
- **Un investigador lleva un conjunto de funciones, no una sola**, porque en
  equipos pequeños acumular es lo normal. Y en cegamiento manda la restricción
  más estricta, no la suma de permisos: quien acumule aplicador y evaluador
  seguirá sin ver la rama, aunque como aplicador podría.

**Lo que queda por decidir con la investigadora principal**: si se admite
acumular funciones. Está como configuración del estudio
(`StudyConfig.permiteAcumularRoles`), no como regla escrita en el código, y el
sistema ya identifica la combinación peligrosa —aplicador + evaluador en la
misma persona— con `Investigador.acumulaFuncionesIncompatibles`.

---

## ⚠️ Lo que destapó el paso 5: la secuencia y el trabajo sin conexión

Al meter el multicentrismo salió un problema que no estaba a la vista, y que
**bloquea el enrolamiento real**.

El contador de la secuencia de aleatorización vive en la base de cada
dispositivo. Dos dispositivos trabajando sin conexión —del mismo centro o de
centros distintos— leen ambos «van consumidas N» y asignan ambos la posición
N+1. Al sincronizar, dos pacientes reclaman la misma posición de la secuencia, y
el reparto deja de ser el que la secuencia dictaba.

Lo grave no es que ocurra: es que **ocurre en silencio**. Nada lo detecta.

Es el mismo problema que resuelven los sobres sellados y numerados que describe
el proyecto: cada sobre se abre una sola vez porque es un objeto físico. El
equivalente digital es repartir **rangos disjuntos de la secuencia** por centro
o por dispositivo — el centro coordinador consume de la 1 a la 40, el segundo de
la 41 a la 80, y así.

Esto conecta con la decisión que ya estaba abierta sobre los sobres físicos
(CLAUDE.md, pendientes §7): son la misma decisión. Conviene resolverla antes del
backend, porque el reparto de rangos condiciona qué envía el servidor a cada
dispositivo.

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
- El modelo por eventos del paso 3, que absorbió los campos del Anexo 4 sin un
  solo cambio estructural. Era la prueba de que la primitiva era la correcta.

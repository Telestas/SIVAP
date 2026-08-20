# Qué falta para completar el MVP

Inventario contra `BASES_MVP_SIVAP.md`, verificado contra el código el 20 ago 2026.
Se actualiza al cerrar cada hito.

> **El reencaminamiento está completo** (`docs/REENCAMINAMIENTO.md`, seis pasos)
> y el **esquema central existe y está verificado** (`docs/BACKEND.md`).
>
> El reparto de la secuencia entre dispositivos —que era el pendiente
> bloqueante— tiene solución en el esquema: tramos disjuntos por dispositivo,
> con una restricción que hace imposible que se solapen, y una clave primaria
> que convierte una colisión silenciosa en un error al sincronizar. Falta
> decidir **quién reparte los tramos y qué hace la app cuando se queda sin
> tramo y sin conexión** (debe dejar de enrolar, no improvisar).

## Hecho (Hito 1 — sin compilar todavía)

| BASES | Qué hay |
|---|---|
| §2 Enrolamiento | Ficha de identidad completa, con contacto y dirección |
| §2 Asignación | Aleatorización simple generada por computadora, semilla registrada, secuencia verificable |
| §2 Consentimiento | Pantalla con documento versionado, declaraciones y firma con el dedo |
| §2 Formularios configurables | La pantalla se construye desde `EstudioFormDefinition`, con los cuatro módulos del Anexo 4 y sus categorías reales |
| §8 Multicéntrico | Centro en la ficha, en cada evento y en cada investigador. Código de paciente con prefijo de centro |
| §9 Minimización | Fuera carné de identidad y dirección |
| BASES §4 Separación de funciones | Seis funciones; la captura va por tipo de hito; el evaluador de desenlaces no ve la rama |
| §2 Auditoría | Solo para corrección de eventos registrados: valor anterior, nuevo, autor, fecha, motivo. En la base, con disparadores que impiden modificarla o borrarla |
| §2 Cegamiento | El sistema solo conoce Protocolo A y B, comprobado por `test/cegamiento_test.dart` |
| §5 Captura por eventos | Línea de tiempo por fases, hitos repetibles, trayectorias incompletas |
| §3 Persistencia cifrada | SQLite + SQLCipher en móvil y escritorio, clave en el Keystore/Keychain. Sin probar en dispositivo |
| §3 Despliegue | Borrador de `deploy/compose.yaml`: Postgres, panel web y TLS con nginx. Falta el backend |
| — | Integración continua | `verificar.yml` analiza y prueba en cada push; `apk.yml` compila y publica el APK como release |
| — | Página de descarga | `web-descarga/` con la estética de la app. Bloqueada por la visibilidad del repositorio — ver `DISTRIBUCION.md` |
| §4 Observador | Solo lectura, cohorte completa |
| §4 Recolector | Crea pacientes y visitas propias, no edita lo enviado |
| §8 Separación ficha/clínica | `Patient` y `Visit` separados, unidos solo por ID interno |

## Falta — infraestructura (nada de esto existe)

Ordenado por lo que más riesgo quita primero.

1. ~~**Persistencia local cifrada**~~ — **hecha (Hito 2)**, pendiente de probar
   en un dispositivo real. SQLite + SQLCipher, clave en el Keystore/Keychain.
   Ver la lista de comprobaciones que exigen dispositivo al final de
   `app/test/almacen_test.dart`.
2. **Backend FastAPI** (BASES §3). El esquema de PostgreSQL ya está y verificado
   (`docs/BACKEND.md`); falta el servicio: autenticación, endpoints y
   sincronización. Requiere decidir dónde se despliega.
3. **Sincronización** (BASES §2, §3). Cola local con timestamp, resolución
   "último gana", log de auditoría. Hoy el estado "en cola" es un interruptor
   de demostración: no hay una sola llamada de red en la app.
4. **Exportación .xlsx** (BASES §2, §3, §8). Con ficha y datos clínicos en
   archivos separados, para poder compartir lo clínico sin identidad. Va en el
   backend, con openpyxl.
5. **Cifrado en tránsito** (BASES §3). TLS. Va con el punto 2.

## Falta — funcionalidad de la app

| BASES | Qué falta | Nota |
|---|---|---|
| §2 | **Registro de investigadores** | El acceso de hoy es de demostración: se elige la función al entrar. En producción viene del servidor con la credencial — y en un ensayo donde los permisos sostienen el cegamiento, que alguien elija los suyos no es aceptable |
| §6 | **Reparto de la secuencia por dispositivo** | Resuelto en el esquema; falta la política de reparto y el servicio que la aplique |
| §4 | **Eliminar** pacientes y visitas (admin) | El repositorio no tiene ningún método de borrado |
| §4 | **Editar la ficha con historial** (admin) | La auditoría hoy solo cubre visitas. `AuditEntity` ya contempla ficha, consentimiento y usuario; el repositorio no |
| §4 | **Gestión de usuarios y roles** (admin) | Sección de la barra lateral sin contenido |
| §6 | **Cargar la secuencia de aleatorización** | Hoy la semilla de demostración está en el código. Hace falta pantalla de administración para fijar la real una vez, ver su consumo y repartir rangos por dispositivo |
| §7 | **Activación del estudio** | El flag `consentimientoAprobadoPorCei` existe pero solo se puede cambiar tocando código |
| — | **Panel de administración: 5 de 6 secciones** | La barra lateral tiene Pacientes, Visitas, Consentimientos, Auditoría, Usuarios y roles, Exportar. Solo Pacientes tiene contenido; el resto cambia el resaltado y no la vista |
| — | **Auditoría completa** | El "Ver todo" del panel no lleva a ninguna parte; solo se ven las últimas seis entradas |
| §7 | **Firma como documento** | La firma se guarda como trazos. Falta convertirla en imagen/PDF junto al texto firmado, que es lo que se archiva |

## Falta — decisiones del equipo, no código

Ninguna de estas la puede resolver quien programa.

1. ~~**Campos exactos por visita**~~ — **hecho**: los cuatro módulos del Anexo 4
   están cargados con sus categorías reales.
2. **Rangos clínicos** de cada campo numérico. Van vacíos a propósito.
   `docs/RANGOS_PENDIENTES.md` está listo para que lo rellene el intensivista, y
   recoge además dos decisiones que conviene tomar a la vez: si el RSBI se
   guarda como categoría o como número, y en qué unidad van dos duraciones.
3. **Semilla y longitud** de la secuencia de aleatorización (BASES §6). Ver la
   recomendación sobre cuándo y dónde fijarla, más abajo.
4. **Aprobación del CEI** (BASES §7). Sin ella no hay pacientes reales.
5. **Nombre final del proyecto**.

## Sobre cuándo fijar la semilla

**Recomendación: todavía no.** Fijarla ahora no desbloquea nada —sin aprobación
del CEI no hay pacientes reales— y una semilla que lleva meses dando vueltas es
una semilla que se filtra. El momento natural es el mismo en que se active el
estudio tras la aprobación.

Pero lo importante no es *cuándo*, sino **dónde**:

> Quien tiene la semilla puede calcular la secuencia entera, y por tanto sabe
> qué rama le toca al próximo paciente. Sabiéndolo, se puede decidir a quién se
> enrola y a quién no. Eso es exactamente el sesgo de selección que la
> aleatorización existe para evitar.

En los ensayos en papel esto se resuelve con sobres opacos, sellados y
numerados. El equivalente aquí:

- La semilla **no vive en la app ni en el repositorio**. Se genera una vez, se
  anota en el expediente del estudio en papel, y la custodia el investigador
  principal.
- Al sistema se carga **solo la secuencia**, cifrada. La semilla sirve después,
  para que un revisor verifique; no hace falta durante el estudio.
- El número **no debe ser una fecha ni nada adivinable** (la de demostración,
  `20260814`, lo es a propósito: es de mentira). Sacarlo de una fuente
  aleatoria física o de `/dev/urandom`, y anotarlo tal cual.
- **Longitud holgada**: al menos el triple de la cohorte prevista. Agotar la
  secuencia a mitad del estudio obliga a una semilla nueva, y eso complica la
  trazabilidad.

Cambio pendiente en el código que se desprende de esto: quitar
`SequentialAllocation.siguienteSinConsumir`, que permite ver la próxima rama sin
consumirla. Hoy lleva un comentario advirtiendo de que no se use desde el
enrolamiento — pero un comentario no impide nada, y la manera de que algo no se
use es que no exista.

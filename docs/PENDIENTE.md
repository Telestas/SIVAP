# Qué falta

Inventario verificado contra el código el 8 sep 2026. Se actualiza al cerrar
cada hito.

> **El riesgo mayor sigue siendo que lo capturado vive en un solo teléfono.**
> El servidor ya sabe recibirlo; la app todavía no sabe enviarlo. Hasta que las
> dos mitades se junten, un teléfono roto o perdido se lleva sus datos consigo
> — la clave de cifrado va en su Keystore, así que no hay de dónde
> recuperarlos.

---

## Hecho

| | |
|---|---|
| Captura por eventos clínicos | Línea de tiempo por fases, hitos repetibles, trayectorias incompletas |
| Campos del Anexo 4 | Los cinco módulos de la revisión, con condicionales y cálculos |
| Cegamiento | Solo Protocolo A y B; el evaluador de desenlaces no ve la rama |
| Separación de funciones | Seis funciones; la captura va por tipo de hito |
| Multicéntrico | Centro en ficha, evento e investigador |
| Minimización | Sin carné ni dirección |
| Auditoría | Correcciones con motivo; solo-inserción por disparadores |
| Persistencia local cifrada | SQLite + SQLCipher, clave en Keystore. Arranca en teléfono real |
| Esquema central | PostgreSQL, 14 garantías comprobadas en cada push |
| Api: sesiones, dispositivos, tramos | 30 pruebas contra Postgres real |
| Reparto de la secuencia | Tramos disjuntos; la colisión pasa de silenciosa a error |
| Api: recepción de lotes | Idempotente, rechazo por registro con su motivo escrito |
| Distribución | APK firmado, con icono, publicado y descargable sin cuenta |
| Integración continua | App, esquema y api en cada push; aviso por Telegram al publicar |

---

## Falta — código

Ordenado por cuánto riesgo quita.

### 1. Sincronización — falta la mitad del cliente

El servidor ya recibe: `POST /api/sincronizacion` acepta pacientes, identidad,
asignación, consentimientos, eventos, valores y auditoría; reenviar un lote no
duplica nada, y lo que se rechaza queda escrito con su motivo en el diario de
lotes.

La app **sigue sin hacer una sola llamada de red**: el «en cola» es un
interruptor de demostración. Falta:

- cliente HTTP y cola de envío, con reintento;
- que la cola deje fuera los datos de demostración, cuyos identificadores no son
  UUID a propósito y el servidor rechazaría;
- pedir el tramo de secuencia al servidor en vez de llevar la secuencia entera;
- **dejar de enrolar** cuando se quede sin tramo y sin conexión. Improvisar una
  asignación es lo que la aleatorización pre-generada existe para evitar.

### 2. Exportación `.xlsx`

Dos archivos: dataset clínico —sin identidad, con la rama en A/B, formato
largo— y ficha de identidad aparte. Es lo que el bioestadista necesita para
poder existir en el proyecto. La vista `dataset_clinico` ya está en el esquema.

### 3. Autenticación real en la app

El acceso de hoy es de demostración: se elige la función al entrar. En un
ensayo donde los permisos sostienen el cegamiento, que alguien elija los suyos
no es aceptable fuera de una demostración.

### 4. El panel de administración

De sus seis secciones **solo «Pacientes» tiene contenido**. Faltan Eventos,
Consentimientos, Auditoría completa —el «Ver todo» no lleva a ninguna parte—,
Usuarios y roles, y Exportar.

### 5. Piezas sueltas

- **Auditoría de la ficha y del consentimiento.** El modelo lo contempla
  (`AuditEntity`), el repositorio solo cubre eventos.
- **Eliminar pacientes y eventos** (BASES §4 se lo atribuye al investigador
  principal). Antes hay que precisar qué significa: el esquema impide borrar un
  paciente aleatorizado, y con razón. Probablemente sea «retirar del
  seguimiento», no borrar la fila.
- **Cargar la secuencia real** desde el panel: hoy la semilla de demostración
  está en el código.
- **Activar el estudio** tras la aprobación del CEI: el flag existe pero solo
  se cambia tocando código.
- **El consentimiento como documento archivable.** Hoy se guardan los trazos de
  la firma; falta componerlos con el texto firmado en algo que se pueda
  archivar.

### 6. Despliegue

`deploy/compose.yaml` está listo y falta ejecutarlo: servidor donde ponerlo,
certificado TLS —el guion lo genera—, y copias de seguridad automáticas en vez
del comando manual.

---

## Falta — decisiones del equipo

Ninguna la puede resolver quien programa, y todas bloquean pacientes reales.

1. **Aprobación del CEI**, por centro. El esquema ya la contempla así.
2. **Cálculo de tamaño muestral.** Sin esto el estudio puede quedar
   subpotenciado.
3. **Semilla y longitud** de la secuencia. Se fijan una vez, antes del primer
   paciente, y se anotan en el expediente en papel.
4. **Tamaño del tramo por dispositivo.** Está en 25 porque lo elegí yo. Tramo
   corto obliga a pedir otro más a menudo, y hace falta conexión para pedirlo;
   tramo largo quema más posiciones si se pierde un teléfono.
5. **Rangos clínicos** de cada campo numérico → `docs/RANGOS_PENDIENTES.md`.
6. **RSBI**: la revisión del Anexo 4 lo retiró junto con el resto de la
   monitorización de la PVE. Decidir si vuelve como número al final de la
   prueba → `docs/ANEXO4_CAMBIOS.md`.
7. **Acceso del evaluador al Módulo 1** y **qué significa retirar a un
   paciente**. Las dos salen de la revisión del Anexo 4, y las dos afectan a la
   validez del estudio → `docs/ANEXO4_CAMBIOS.md`.
8. **Umbral de VMI para incluir**: el protocolo dice >24 h, el proyecto >48 h.
9. **Acumulación de funciones**: si un médico puede cumplir varias. Está como
   configuración; la combinación peligrosa está identificada.
10. **Sobres sellados**: si la app los reemplaza o coexisten.
11. **Corriente cualitativa**: si entra al MVP.
12. **Nombre final del sistema.**

---

## Falta — comprobar en un teléfono

La app arranca, que era la incógnita mayor: significa que SQLCipher se carga.
Queda lo que ninguna prueba automática puede hacer:

1. Que el archivo `.db` **no contenga el nombre del paciente en claro**.
2. Que reabrir con otra clave falle.
3. **Enrolar → cerrar la app → reabrir → enrolar.** El segundo paciente debe
   recibir la posición siguiente de la secuencia, no la primera. Es el fallo
   que más daño haría y sigue sin comprobarse.

Dos que estaban en esta lista ya no lo están: que dos borradores del mismo hito
no puedan coexistir y que una corrección sin motivo no entre. Las comprueba
`test/esquema_local_test.dart` contra un SQLite de verdad, sin cifrar — la
forma del esquema se puede probar sin teléfono; el cifrado no.

Y la que más vale de todas: **que un intensivista capture una PVE completa**.
Mientras no haya sincronización ni exportación, todavía se pueden cambiar los
campos sin arrastrar datos ya capturados.

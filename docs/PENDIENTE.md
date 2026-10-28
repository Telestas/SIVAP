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
| Separación de funciones | Cinco funciones; la captura va por tipo de hito |
| Multicéntrico | Centro en ficha, evento e investigador |
| Minimización | Sin carné ni dirección |
| Auditoría | Correcciones con motivo; solo-inserción por disparadores |
| Persistencia local cifrada | SQLite + SQLCipher, clave en Keystore. Arranca en teléfono real |
| Esquema central | PostgreSQL, 14 garantías comprobadas en cada push |
| Api: sesiones, dispositivos, tramos | 30 pruebas contra Postgres real |
| Reparto de la secuencia | Tramos disjuntos; la colisión pasa de silenciosa a error |
| Api: recepción de lotes | Idempotente, rechazo por registro con su motivo escrito |
| Cola de envío | Acuse por registro; los datos de demostración quedan fuera |
| Sincronización en la app | Pantalla propia: servidor, sesión, envío y motivos de rechazo |
| Alertas | Seguimiento a los 7, 14 y 28 días, y paciente listo para evaluar |
| Distribución | APK firmado, con icono, publicado y descargable sin cuenta |
| Acceso del panel web | Firebase Authentication; función, centro y permisos salen del perfil aprovisionado |
| Lectura del panel web | Pacientes, identidad permitida, asignación, eventos y auditoría se leen de Firestore |
| Vistas del panel web | Eventos, consentimientos, auditoría completa y perfiles del centro |
| Recuperación de acceso web | Solicitud de cambio de contraseña desde el propio acceso |
| Integración continua | App, esquema y api en cada push; aviso por Telegram al publicar |

---

## Falta — código

Ordenado por cuánto riesgo quita.

### 1. Sincronización — falta la mitad del cliente

El servidor ya recibe: `POST /api/sincronizacion` acepta pacientes, identidad,
asignación, consentimientos, eventos, valores y auditoría; reenviar un lote no
duplica nada, y lo que se rechaza queda escrito con su motivo en el diario de
lotes.

Del lado del cliente ya están el cliente HTTP y la cola: reúne lo pendiente, lo
manda en un lote y marca solo lo que el servidor aceptó. Los datos de
demostración quedan fuera y los borradores tampoco viajan.

La app ya la usa: hay pantalla de sincronización con la dirección del servidor,
el acceso, el envío y —lo que más importa— el motivo por el que el servidor no
admitió algo. El identificador del aparato se guarda entre arranques, que era
necesario: si se regenerara, el servidor le daría un tramo nuevo de la
secuencia cada vez.

El envío es **manual, a propósito**. Un reintento automático en bucle sobre una
conexión que va y viene gasta batería y no añade nada que un botón no dé; y la
captura no depende de él en ningún caso.

Android ya solicita tramos a una función privilegiada, los guarda en SQLite
cifrado y detiene el enrolamiento al agotarse. Falta desplegar la función,
cargar fuera de Git la secuencia aprobada y verificar el ciclo completo en
teléfonos con conexión intermitente. La compilación distribuida sigue en modo
demostración hasta cerrar las aprobaciones del estudio.

Y dos cosas menores: que el detalle de los rechazos sobreviva a cerrar la app
—hoy vive en memoria, aunque el dato rechazado no se pierde— y poner etiqueta
al aparato para distinguirlo en el panel.

### 2. Exportación `.xlsx`

Dos archivos: dataset clínico —sin identidad, con la rama en A/B, formato
largo— y ficha de identidad aparte. Es lo que el bioestadista necesita para
poder existir en el proyecto. La vista `dataset_clinico` ya está en el esquema.

### 3. Autenticación real en la app móvil

Android ya autentica con Firebase y toma función y centro del perfil
aprovisionado mediante el proxy HTTPS de Cloudflare. La base cifrada se vincula
a un UID y una sesión validada puede restaurarse sin conexión. Falta comprobar
el flujo en un teléfono cubano sin VPN y decidir cuánto
tiempo puede seguir vigente un perfil guardado sin red cuando sus permisos
cambien en el servidor. iOS aún no tiene configuración Firebase registrada.

### 4. Terminar el panel de administración

Pacientes, Eventos, Consentimientos, Auditoría completa y Usuarios y roles ya
consultan la vista consolidada. Los perfiles se siguen aprovisionando fuera del
navegador: ningún cliente puede conceder funciones ni cambiar de institución.

Falta conectar «Exportar datos» con el endpoint `.xlsx` descrito en el punto 2.
La pantalla ya deja explícita la separación entre ficha identificable y dataset
clínico, pero no ofrece una descarga ficticia mientras el backend no la genere.

### 5. Piezas sueltas

- **Auditoría de la ficha y del consentimiento.** Las altas ya generan entradas
  de auditoría. Si se habilitan rectificaciones de identidad o nuevas firmas,
  requieren una operación versionada con motivo; hoy se rechaza la segunda firma.
- **Eliminar pacientes y eventos** (BASES §4 se lo atribuye al investigador
  principal). Antes hay que precisar qué significa: el esquema impide borrar un
  paciente aleatorizado, y con razón. Probablemente sea «retirar del
  seguimiento», no borrar la fila.
- **Cargar la secuencia real** desde el panel: hoy la semilla de demostración
  está en el código.
- **Activar el estudio**: la app ya lee aprobación por centro y texto vigente
  de Firestore. Falta cargar los datos reales aprobados fuera del repositorio y
  preparar la secuencia clínica antes de enrolar. Spark utiliza reservas
  preparadas por CLI y reclamadas de forma exclusiva por el teléfono. El
  proyecto actual permite pruebas integradas con cuenta y sincronización en
  `preproduccion`; el consentimiento y la secuencia de prueba no habilitan
  pacientes del estudio al cambiar a producción. Ver `DISTRIBUCION.md`.
- **Consentimiento archivable.** El texto exacto y la firma ya se conservan y
  se descargan como HTML autónomo imprimible. Falta acordar si el archivo legal
  de custodia debe ser PDF/A y quién guarda su copia fuera de la app.
- **Exportación.** El panel descarga XLSX clínico e identidad en archivos
  separados y registra cada solicitud en auditoría. Falta validar el formato
  final del dataset con el equipo de análisis y el procedimiento de custodia
  del archivo identificable.

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

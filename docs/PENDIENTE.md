# Qué falta

Inventario verificado contra el código el 21 ago 2026. Se actualiza al cerrar
cada hito.

> **El riesgo mayor hoy no es que falte una funcionalidad: es que la app no
> sincroniza.** Lo que se capture ahora vive en un solo teléfono. Si ese
> teléfono se rompe o se pierde, se pierde con él — y la clave de cifrado va en
> su Keystore, así que no hay forma de recuperarlo desde otro sitio.

---

## Hecho

| | |
|---|---|
| Captura por eventos clínicos | Línea de tiempo por fases, hitos repetibles, trayectorias incompletas |
| Campos del Anexo 4 | Los cuatro módulos con sus categorías reales |
| Cegamiento | Solo Protocolo A y B; el evaluador de desenlaces no ve la rama |
| Separación de funciones | Seis funciones; la captura va por tipo de hito |
| Multicéntrico | Centro en ficha, evento e investigador |
| Minimización | Sin carné ni dirección |
| Auditoría | Correcciones con motivo; solo-inserción por disparadores |
| Persistencia local cifrada | SQLite + SQLCipher, clave en Keystore. Arranca en teléfono real |
| Esquema central | PostgreSQL, 14 garantías comprobadas en cada push |
| Api: sesiones, dispositivos, tramos | 30 pruebas contra Postgres real |
| Reparto de la secuencia | Tramos disjuntos; la colisión pasa de silenciosa a error |
| Distribución | APK firmado, con icono, publicado y descargable sin cuenta |
| Integración continua | App, esquema y api en cada push; aviso por Telegram al publicar |

---

## Falta — código

Ordenado por cuánto riesgo quita.

### 1. Sincronización

Hoy la app **no hace una sola llamada de red**: el «en cola» es un interruptor
de demostración.

- **En la app**: cliente HTTP, cola de envío, `Ids.nuevo` a UUIDv4 (el esquema
  usa `uuid` y la app genera `p-3f9a…`), pedir el tramo al servidor en vez de
  llevar la secuencia entera, y **dejar de enrolar** cuando se quede sin tramo
  y sin conexión. Improvisar una asignación es lo que la aleatorización
  pre-generada existe para evitar.
- **En la api**: recepción idempotente de eventos y auditoría, y el diario de
  lotes que el esquema ya prevé.

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
6. **RSBI: número o categoría.** Hoy categoría, como dice el Anexo 4. Un 92 y
   un 104 caen en la misma y el dataset deja de distinguirlos. Al revés no
   tiene vuelta.
7. **Unidades** de la detención de sedación y del tiempo entre PVE y
   extubación. Hoy horas con un decimal.
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
3. Que el disparador de auditoría aborte un `UPDATE`.
4. Que dos borradores del mismo hito no puedan coexistir.
5. **Enrolar → cerrar la app → reabrir → enrolar.** El segundo paciente debe
   recibir la posición siguiente de la secuencia, no la primera. Es el fallo
   que más daño haría y sigue sin comprobarse.

Y la que más vale de todas: **que un intensivista capture una PVE completa**.
Mientras no haya sincronización ni exportación, todavía se pueden cambiar los
campos sin arrastrar datos ya capturados.

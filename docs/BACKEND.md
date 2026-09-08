# Backend — esquema central y decisiones

Estado: **el esquema existe y está verificado** (`api/migraciones/001_esquema_inicial.sql`)
y el servicio FastAPI cubre sesiones, dispositivos, reparto de la secuencia y
recepción de lotes. Falta la mitad del cliente: la app todavía no hace una sola
llamada de red.

El esquema corre sobre PostgreSQL 16 y sus garantías se comprueban en cada push
(`api/pruebas/esquema_test.sql`, trabajo `esquema` de la integración continua).

## La idea de fondo

La base del dispositivo guarda lo que un investigador capturó. La base central
guarda **el estudio**, y va a sobrevivir a la app: cuando alguien pregunte dentro
de tres años qué decía un campo en agosto de 2026, la respuesta sale de aquí.

Por eso el esquema hace valer por sí mismo tres cosas que no pueden depender de
que la aplicación esté bien escrita:

1. **La auditoría no se puede modificar ni borrar.** Disparadores más `REVOKE`,
   de forma que ni la propia api tiene el privilegio.
2. **Dos pacientes no pueden ocupar la misma posición de la secuencia.** Clave
   primaria compuesta, más un disparador que comprueba que la rama asignada es
   la que la secuencia dictaba en esa posición.
3. **Quien analiza no puede leer la identidad.** El rol `sivap_analista` no
   tiene permiso sobre la tabla `identidad`, y las vistas van con
   `security_invoker` para que ese permiso no se pueda esquivar por detrás.

Una aplicación se reescribe mal cualquier día. Estas tres, no.

## Las tablas

| Grupo | Tablas |
|---|---|
| Configuración | `institucion`, `definicion_formulario` |
| Personas | `investigador`, `investigador_rol`, `dispositivo` |
| Aleatorización | `secuencia`, `secuencia_rango`, `asignacion` |
| Pacientes | `paciente`, `identidad`, `consentimiento` |
| Clínico | `evento`, `evento_valor` |
| Trazabilidad | `auditoria`, `lote_sincronizacion` |
| Vistas | `evento_valor_vigente`, `dataset_clinico`, `investigador_con_cegamiento_comprometido` |

## Decisiones que conviene entender antes de tocarlo

### El reparto de la secuencia resuelve el problema del trabajo sin conexión

Era el pendiente bloqueante. `secuencia_rango` da a cada dispositivo un tramo
propio —`[1,50)`, `[50,90)`— y una restricción `EXCLUDE` hace **imposible** que
dos tramos se solapen: no por disciplina, sino porque la base rechaza el
`INSERT`.

Es el equivalente digital de los sobres sellados y numerados que describe el
proyecto: cada sobre se abre una vez porque es un objeto físico; cada tramo lo
consume un dispositivo porque nadie más lo tiene.

Y si aun así dos dispositivos mal configurados intentaran la misma posición, la
clave primaria de `asignacion` los detiene al sincronizar. **La colisión pasa de
ser silenciosa a ser un error.** Esa es la diferencia que importa.

### El código de paciente sale de la posición de aleatorización

`HC-041` es el paciente que ocupó la posición 41. Como las posiciones vienen de
tramos disjuntos, los códigos no chocan aunque se generen sin conexión — y
además atan el código a su asignación, que es la práctica habitual en ensayos.

Esto sustituye al correlativo por centro que usa hoy la app, que sí podía
repetirse entre dispositivos.

### Los valores clínicos son versionados y de solo añadir

Una corrección no sobrescribe: inserta una versión nueva. La vista
`evento_valor_vigente` da el valor actual; la tabla conserva todos.

Así la resolución «último gana» de la sincronización no pierde nada, y el
historial completo de cada dato existe sin tener que reconstruirlo desde la
auditoría. En un ensayo clínico, poder demostrar qué decía un campo en una fecha
concreta no es una comodidad: es lo que se pregunta en una inspección.

### La semilla no está en la base

`secuencia` guarda el código binario, no la semilla (CLAUDE.md §7). Quien
tuviera la semilla podría calcular la secuencia entera y saber qué rama le toca
al próximo paciente.

**Esto obligó a corregir también la base del dispositivo**, que sí tenía columna
para la semilla. Ya no.

### La aprobación del CEI es por centro

`institucion.cei_aprobado`, no un flag global: el cronograma admite que un centro
empiece antes que otro, y un `CHECK` exige que la aprobación venga con su código
y su fecha.

### Los borradores no se sincronizan

Solo llegan a la base central los eventos **registrados**. Sincronizar datos a
medio teclear llenaría el estudio de registros incompletos que nadie sabría si
son definitivos.

### Un paciente aleatorizado no se borra

`asignacion` referencia a `paciente` sin `CASCADE`: intentar borrarlo falla. La
posición se consumió y eso es permanente. Hacer desaparecer a un paciente ya
asignado es la puerta trasera del sesgo de selección; una retirada del estudio se
**registra**, no se borra.

Esto contradice a medias la tabla de roles de BASES §4, que da al investigador
principal permiso para eliminar. Habría que precisar qué significa «eliminar»
ahí: probablemente retirar del seguimiento, no borrar la fila.

### La definición de formularios va como documento, no repartida en tablas

La unidad que importa es la **versión completa**: un dataset exportado
corresponde a exactamente una versión de la definición. Trocearla en tablas
haría posible tener media definición vieja y media nueva conviviendo, y entonces
nadie sabría contra qué se capturó cada dato.

### La recepción rechaza registros, no lotes

`POST /api/sincronizacion` guarda cada registro en su propio punto de guardado.
Lo que falla se rechaza con el motivo que dio PostgreSQL, escrito en
`lote_sincronizacion.detalle`, y lo demás entra.

La alternativa —todo o nada— parece más limpia y es peor: un teléfono con un
solo registro problemático no conseguiría sincronizar nunca, y con esta
conectividad eso no es una hipótesis. Además así la respuesta a «¿esto llegó?»
queda escrita, que es la pregunta que se hace sola cuando la conexión va y
viene.

Con una excepción deliberada: un envío que ni siquiera se puede leer —un tipo
de evento que no existe, una fecha imposible— corta el lote entero con un 422.
Eso no es un dato de campo discutible, es la app enviando algo que no debería
existir, y conviene verlo de golpe y no diluido entre los rechazos.

### La autoría sale de la sesión, no del envío

El evento dice qué se capturó; **quién lo capturó lo decide el token**. Aceptar
un `recolector_id` del cuerpo de la petición permitiría a cualquier dispositivo
atribuir capturas a cualquier persona, y entonces el registro de auditoría
dejaría de significar algo.

Se sostiene porque un dispositivo pertenece a una sola persona, que es la
decisión que ya tomaba el registro de dispositivos: si dos médicos comparten
teléfono, se registra dos veces con identificadores distintos.

### El CEI se comprueba también aquí

La app sabe qué centros están aprobados —lo recibe en la configuración del
estudio— y aun así el servidor lo vuelve a mirar antes de admitir un paciente.
Un dispositivo con configuración vieja, o con una versión de la app anterior a
la comprobación, no debe poder meter pacientes reales donde todavía no se puede
reclutar.

Se rechaza ese paciente, no el lote: queda en la cola del dispositivo y entra
solo en cuanto el centro quede aprobado.

## Lo que falta decidir

1. **Quién reparte los tramos de secuencia y cuándo.** El dispositivo pide y el
   servidor entrega; falta el umbral con el que la app pide el siguiente, y qué
   hace si se queda sin tramo y sin conexión. **Esa última es la pregunta
   importante**: o deja de enrolar, o improvisa. Debe dejar de enrolar.
2. **Autenticación en la app.** El token de sincronización ya existe y caduca.
   Falta que la app valide la credencial contra el dispositivo para abrirse sin
   conexión: la captura no puede depender de un token vivo (CLAUDE.md §12).
3. **Auditoría de lo que el servidor descarta.** «Último gana» resuelve el
   conflicto y la versión anterior se conserva, así que no se pierde nada. Falta
   decidir si además queda una entrada de auditoría cuando dos dispositivos
   corrigen el mismo campo, y quién la firma: el conflicto lo resolvió el
   servidor, no una persona.

**Resuelto**: los identificadores. `Ids.nuevo` genera UUIDv4 y el esquema los
recibe tal cual. Aflojar el tipo de la columna a texto habría costado la
validación, la mitad del índice y el doble de espacio a cambio de que un
registro se leyera algo mejor.

## Cómo probar el esquema en local

```bash
docker run --rm -d --name sivap-db -e POSTGRES_PASSWORD=x postgres:16
docker exec -i sivap-db psql -U postgres -v ON_ERROR_STOP=1 -q \
  < api/migraciones/001_esquema_inicial.sql
docker exec -i sivap-db psql -U postgres -v ON_ERROR_STOP=1 -q \
  < api/pruebas/esquema_test.sql
docker rm -f sivap-db
```

Las pruebas van dentro de una transacción que se deshace al final: no dejan
rastro y se pueden repetir sobre la misma base.

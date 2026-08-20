# Backend — esquema central y decisiones

Estado: **el esquema existe y está verificado** (`api/migraciones/001_esquema_inicial.sql`).
El servicio FastAPI todavía no.

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

## Lo que falta decidir antes de escribir la api

1. **Identificadores.** El esquema usa `uuid`; la app genera cadenas con prefijo
   (`p-3f9a…`). Hay que pasar `Ids.nuevo` a UUIDv4 antes de la primera
   sincronización. Es preferible cambiar el cliente que aflojar el tipo de la
   columna: `uuid` valida, indexa mejor y ocupa la mitad.
2. **Quién reparte los tramos de secuencia y cuándo.** Lo natural es que el
   investigador principal asigne un tramo a cada dispositivo al registrarlo, y
   que el dispositivo pida uno nuevo cuando le queden pocas posiciones. Falta
   decidir el umbral y qué hace la app si se queda sin tramo y sin conexión.
   **Esa última es la pregunta importante**: o deja de enrolar, o improvisa. Debe
   dejar de enrolar.
3. **Autenticación.** Tokens de sesión con caducidad, y qué pasa cuando un
   dispositivo lleva semanas sin conectar. La captura no puede depender de un
   token vivo (CLAUDE.md §12), así que la credencial se valida contra el
   dispositivo y el token solo hace falta para sincronizar.
4. **Qué hace el servidor con un conflicto.** «Último gana» está decidido, pero
   falta si el servidor genera una entrada de auditoría cuando descarta una
   versión, y quién la firma.

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

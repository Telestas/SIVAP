# Firebase: backend de consolidación

Este directorio define el despliegue de Firebase del proyecto `sivap-f5060`.
La app móvil conserva SQLite cifrado y la cola local; Firestore solo recibe una
copia confirmada durante la sincronización. GitHub Pages sigue publicando la
página de descarga del APK. El panel web se publica en Cloudflare Pages en
<https://sivap.pages.dev/>. Firebase Hosting redirige la URL anterior hacia ese
panel; Authentication y Firestore permanecen en el proyecto Firebase.

## Estado y límites

No cree datos clínicos ni habilite enrolamiento real hasta que estén aprobados el
CEI, la custodia de datos y la política de aleatorización. Las reglas impiden
leer o escribir secuencias y tramos desde el cliente. La función autenticada
`solicitarTramo` reparte rangos exclusivos sin publicar la secuencia completa.
`Protocolo A` y `Protocolo B` son las únicas etiquetas del estudio.

La región seleccionada es `nam5` (multirregión de Estados Unidos central), para
priorizar disponibilidad y durabilidad. Esa elección será permanente al crear la
base; documente su aprobación institucional fuera del repositorio. Inicialice la
base en modo producción, nunca en modo de prueba.

## Operación

Una persona puede crear una cuenta con correo y contraseña, verificar el correo
y solicitar acceso indicando el código de un centro existente. También puede
solicitar acceso si ya tiene una cuenta en Firebase Authentication. La solicitud
no concede acceso clínico. El investigador principal ve únicamente las
solicitudes de su centro en «Usuarios y roles» y aprueba una función permitida;
la aprobación crea el perfil y cierra la solicitud en un mismo lote. El rol de
investigador principal sigue requiriendo aprovisionamiento administrativo.
Para crear otro principal, un operador con permisos administrativos en Firebase
verifica primero la identidad y crea la cuenta en Authentication (o usa la
cuenta que esa persona ya verificó). Copia su UID y crea en Firestore el
documento `investigadores/{uid}` con `nombre` y `correo` de esa cuenta,
`institucion_codigo` del centro autorizado y `roles` como arreglo con el único
valor `investigadorPrincipal`. Si existe una solicitud pendiente para el mismo
UID, el operador debe resolverla administrativamente para que no siga figurando
como pendiente; el panel no puede conceder ese rol. El operador registra esta
asignación en el expediente administrativo del estudio. Esta operación exige
acceso a la consola de Firebase y no se realiza desde una cuenta solicitante.
Cada perfil,
con el UID de Firebase Authentication como identificador, debe contener
`nombre`, `institucion_codigo` y `roles`; `institucion_nombre` es opcional. El
nombre visible se lee de `instituciones/{codigo}.nombre` si está disponible:
puede cambiar sin modificar el código estable ni actualizar todos los perfiles.
Para agregar otro centro se crea otro documento de institución y se aprovisionan
sus perfiles con ese código; no hace falta recompilar la app. Las
reglas requieren además que cada documento sincronizado incluya
`institucion_codigo` y `autor_uid`.

Antes del primer paciente, un operador autorizado carga fuera de Git:

- `instituciones/{codigo}` con `nombre` y `cei_aprobado: true` solo para los
  centros aprobados por su CEI. Mantenga el código estable aunque cambie el
  nombre visible.
- `estudios/livere/configuracion/consentimiento` con `aprobado: true`,
  `version`, `codigo_cei`, `vigente_desde`, `parrafos` y `declaraciones` del
  documento exacto aprobado. El texto real y el expediente CEI no van en Git.
- `aleatorizacion/activa` con `etiqueta`, `codigo_binario` (solo `0` y `1`),
  `siguiente: 1` y `tamano_tramo` aprobado por el equipo. La semilla no se
  carga en Firebase.

Android toma rol y centro de `investigadores/{uid}` y vincula la base local
cifrada a ese UID. Una sesión validada puede reabrirse sin conexión desde la
caché del perfil. Enviar datos y pedir tramos exige conexión. Al agotarse un
tramo, hay que sincronizar sus asignaciones antes de recibir el siguiente.
Las reglas comprueban rama y posición contra el tramo y una marca única por
posición en la misma transacción.
La captura móvil conserva en SQLCipher el texto vigente leído de Firestore y
archiva una instantánea junto a cada firma. Si falta la aprobación del centro,
el consentimiento o un tramo, el enrolamiento se detiene.

El panel web autentica primero y solo entonces carga pacientes, asignaciones,
identidades permitidas, eventos y auditoría. Permite al investigador principal
aprobar solicitudes de su centro. Los datos clínicos siguen en modo de solo
lectura en el navegador: no enrola ni corrige desde allí.

Tras crear la base y probar las reglas con Emulator Suite:

```bash
firebase deploy --only firestore
cd firebase/functions && npm install && cd ../..
firebase deploy --only functions
firebase deploy --only hosting  # solo redirección a Cloudflare Pages
```

El despliegue de `solicitarTramo` requiere el plan Blaze: Cloud Build y
Artifact Registry no se habilitan en Spark. Hasta que la función esté publicada
y exista la secuencia real, la app detiene el enrolamiento por falta de tramo.

No guarde cuentas de servicio, tokens de CI ni archivos de configuración privados
en el repositorio. Las reglas son código: todo cambio requiere pruebas de permisos
antes de desplegarlo.

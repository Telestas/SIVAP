# Firebase: backend de consolidación

Este directorio define el despliegue de Firebase del proyecto `sivap-f5060`.
La app móvil conserva SQLite cifrado y la cola local; Firestore solo recibe una
copia confirmada durante la sincronización. GitHub Pages sigue publicando la
página de descarga del APK. Firebase Hosting, si se activa, sirve únicamente el
panel web compilado en `app/build/web`.

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

Los perfiles se aprovisionan desde una herramienta administrativa confiable; la
app no puede crear usuarios, elevar roles ni cambiar instituciones. Cada perfil,
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
identidades permitidas, eventos y auditoría. Es de solo lectura: no enrola ni
corrige desde el navegador, incluso si el perfil tiene permisos de escritura en
la app móvil.

Tras crear la base y probar las reglas con Emulator Suite:

```bash
firebase deploy --only firestore
cd firebase/functions && npm install && cd ../..
firebase deploy --only functions
firebase deploy --only hosting
```

El despliegue de `solicitarTramo` requiere el plan Blaze: Cloud Build y
Artifact Registry no se habilitan en Spark. Hasta que la función esté publicada
y exista la secuencia real, la app detiene el enrolamiento por falta de tramo.

No guarde cuentas de servicio, tokens de CI ni archivos de configuración privados
en el repositorio. Las reglas son código: todo cambio requiere pruebas de permisos
antes de desplegarlo.

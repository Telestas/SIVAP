# Distribución del APK

## Estado: funcionando

**https://sivap.pages.dev/descargar/** — la página comparte el dominio del
panel y ofrece el APK de la última versión publicada. La URL antigua de GitHub
Pages redirige a esta ruta.

## Prueba del flujo sin Firebase

En el acceso de la app, **Probar flujo sin conexión** abre una sesión separada
con datos ficticios. Permite enrolar, guardar, registrar un consentimiento de
prueba y capturar eventos. Usa una secuencia ficticia ya generada. Todo queda en
memoria, no se sincroniza y se borra al salir de la prueba. Nunca introducir
datos de pacientes reales en esta sesión.

## Pruebas integradas con cuenta y sincronización

Desde v0.2.6 el proyecto puede configurarse como `preproduccion` para ensayar con
la cuenta Firebase habitual, SQLite cifrado, firmas, eventos y sincronización.
La app muestra una banda permanente: solo pacientes ficticios. Los datos
permanecen al cerrar y se consultan en el panel web. El consentimiento de prueba
se identifica como ficticio, sin declarar una aprobación clínica inexistente.

Se mantiene Spark. Cloud Functions requiere Blaze, por lo que la CLI reserva
tramos de la secuencia en una transacción administrativa. Al pulsar **Solicitar
tramo**, la app reclama la reserva de su cuenta en un único dispositivo. Las
reglas impiden cambiar sus ramas o reclamarla desde otro teléfono. El servicio
no usa contraseñas de administrador en la app; la CLI utiliza la sesión local
de Firebase del operador. La secuencia completa queda privada en Firestore.

Preparar por primera vez un proyecto de pruebas sin secuencia clínica:

```bash
npm --prefix firebase ci
firebase login
node firebase/administrar.mjs preparar-preproduccion --proyecto ID --centro CODIGO
node firebase/administrar.mjs reservar --proyecto ID --uid UID_DE_LA_CUENTA
```

La reserva pendiente se conserva si se repite el comando. Después de reclamarla,
la CLI puede preparar la siguiente; antes de recogerla en el mismo teléfono,
la app exige sincronizar los pacientes del tramo anterior. El reparto avanza
siempre y no repite posiciones. La secuencia inicial de preproducción contiene
400 posiciones ficticias, con reservas de 50. Se genera fuera de la app.

Si Node falla inmediatamente con `ETIMEDOUT` en una red de doble pila lenta,
puede ejecutarse con `node --no-network-family-autoselection`.

### Limpieza antes de uso clínico

No basta borrar pacientes del servidor: el teléfono conserva la base cifrada,
los acuses y las asignaciones pendientes. La limpieza de pruebas debe incluir
identidades, pacientes, asignaciones, posiciones, consentimientos, eventos,
auditoría de prueba, lotes, tramos y reservas; también hay que reiniciar la
base local de cada aparato de pruebas. Conservar las cuentas y perfiles.

Antes de activar producción se debe cambiar el entorno a `produccion`, cargar
el consentimiento real aprobado y una nueva secuencia clínica, y registrar la
aprobación de los centros. Las reglas vuelven a exigir esas aprobaciones fuera
de preproducción. No se reutiliza la secuencia de prueba ni se limpia una base
que ya contenga pacientes del estudio. Esta entrega no borra ningún dato.

## Acceso desde Cuba

Se observó una respuesta HTML `403 Forbidden` de Identity Toolkit sin VPN,
mientras la misma cuenta y configuración funcionan con VPN. Google indica que
restringe algunos servicios de Cloud en Cuba:
<https://docs.cloud.google.com/billing/docs/how-to/create-billing-account>.
Se verificó que las claves Android y web permiten `identitytoolkit.googleapis.com`
y `securetoken.googleapis.com`, las API necesarias para autenticación. Junto con
el acceso correcto por VPN, esto apunta a una restricción por origen de la
conexión, no a un problema de contraseña o de lista de API de la clave; no
identifica por sí solo cuál servicio aplica la restricción. La app muestra un
mensaje breve para ese caso. Una configuración de Firebase no puede convertir
ese HTML 403 en una sesión válida. El acceso real requiere una ruta de red que
alcance los servicios de Firebase. La prueba local descrita arriba funciona sin
esa ruta.

En la web, Firefox mostró que la petición previa `OPTIONS` a
`identitytoolkit.googleapis.com/v1/accounts:signInWithPassword` recibe `403`
sin `Access-Control-Allow-Origin` desde Cuba. Por eso aparece también un error
CORS: es una consecuencia de la respuesta 403, no una cabecera que podamos
añadir desde Hosting. Desde otra red se comprobó que la misma petición `OPTIONS`
recibe `200` con la cabecera CORS correcta y que un `POST` vacío, sin credenciales,
recibe el error JSON esperado. Los avisos de WebGL, TrustedTypes y mapas de código
no explican el fallo de autenticación.

Para solicitar una investigación a Firebase Support, aportar la hora y zona
horaria, URL del proyecto, método de acceso (web, Wi-Fi o datos móviles) y
captura de la respuesta `OPTIONS` 403 sin compartir contraseñas ni tokens. Pedir
que confirmen si Firebase Authentication y Firestore admiten el acceso desde las
redes cubanas afectadas y si existe un ajuste oficial para habilitarlo. Hasta
recibir esa respuesta, la VPN es la vía de pruebas que se ha comprobado en el
teléfono. Cambiar `authDomain` o las cabeceras del sitio no modifica la llamada
directa del SDK a Identity Toolkit. Hosting en Spark tampoco proporciona un
proxy HTTPS arbitrario para esa llamada.

### Ruta con Cloudflare Pages, como en Velanus

El proyecto Velanus resolvió el bloqueo observado desde Cuba alojando la web en
Cloudflare Pages y reenviando Firebase Authentication, renovación de sesión y
Firestore desde Pages Functions del mismo dominio. El navegador habla con
Cloudflare y las funciones hablan con Google. Firebase sigue validando cuentas,
tokens y reglas; Cloudflare recibe las credenciales y los datos clínicos en
tránsito. Esto exige revisar la autorización para ese intermediario antes de
emplearlo con pacientes reales.

SIVAP tiene preparada esa ruta en `functions/` y `app/web_assets/`. En un
dominio `*.pages.dev`, el cliente web dirige Authentication y Secure Token al
proxy y configura Firestore para ese mismo host; en Firebase Hosting conserva
las llamadas directas. El proxy solo admite rutas y métodos del proyecto
SIVAP, no almacena respuestas y no añade privilegios de administración.

El proyecto Pages de pruebas es `sivap`; la URL publicada es
<https://sivap.pages.dev/>. La primera publicación se verificó desde otra red:
la web respondió `200`; Authentication devolvió `MISSING_EMAIL` JSON a una
petición vacía, y Firestore devolvió su rechazo JSON normal a una consulta sin
sesión. Una persona del equipo confirmó que pudo iniciar sesión y entrar al
panel desde Cuba sin VPN el 28 de octubre de 2026. Aún falta comprobar desde
esa red la renovación de sesión y las operaciones de lectura y escritura del
flujo completo.

Para repetir la publicación, preparar el andamiaje web con
`tool/preparar_android.sh web`, compilar con
`flutter build web --release --no-wasm-dry-run`, ejecutar
`tool/preparar_pages.sh` desde `app/` y publicar `app/build/pages` con
`wrangler pages deploy app/build/pages --project-name sivap --branch main`
desde la raíz. El paquete de Pages omite las copias locales de CanvasKit porque
Flutter ya lo descarga de `gstatic.com`; esto redujo la subida de 42 MB a
menos de 6 MB en esta red. La comprobación desde Cuba debe incluir la carga de
CanvasKit además del inicio de sesión.

Añadir `sivap.pages.dev` a los dominios autorizados de Firebase Authentication
y, si corresponde, a las restricciones de referencia de la clave web. Probar
renovación de sesión, lecturas, escrituras y sincronización desde Cuba sin VPN
antes de usarlo para el estudio. La URL anterior de `web.app` redirige al
panel de Cloudflare Pages; no debe alojar otra copia de Flutter.

### Acceso móvil sin VPN

Android usa ahora `FirebaseRestMovil` sobre `https://sivap.pages.dev`. El inicio
de sesión, registro, verificación, recuperación, renovación del token, perfil,
configuración, solicitudes de acceso, aprobación, reserva de tramos y envío de
lotes pasan por Cloudflare Pages Functions. El SDK nativo ya no se inicializa en
Android. Firebase sigue validando las credenciales; Firestore recibe el ID token
del usuario y aplica las reglas de rol y centro existentes.

El token de renovación y el último perfil aprobado viven en Android Keystore.
La base SQLite cifrada conserva la captura y la cola sin conexión. Los tramos
se reclaman con una transacción que lee la reserva y crea el documento del
dispositivo en un solo commit. Cada lote se confirma junto a su acuse, y una
repetición consulta primero ese acuse. Firestore puede abortar una transacción
en conflicto; el cliente reintenta la operación completa hasta tres veces.

Las pruebas automáticas cubren el origen de las peticiones, la codificación
Firestore, los tiempos del servidor, la reserva no transferible, el acuse
idempotente y la aprobación atómica. Desde fuera de Cuba se comprobó que la
ruta `documents:beginTransaction` publicada responde en JSON. Falta probar
desde un teléfono cubano sin VPN el inicio y renovación de sesión, la lectura,
la solicitud de tramo y la sincronización con datos ficticios. Esa comprobación
de campo determina si Cloudflare resuelve el bloqueo también en Android.

La versión 0.2.9 alcanzó el proxy, pero en el teléfono cubano informó un fallo
de conexión antes de recibir HTTP; Chrome en ese mismo teléfono sí abre el panel
y permite iniciar sesión sin VPN. La versión 0.2.10 cambia el transporte Android
al motor de red Chromium/Cronet con HTTP/3, DNS del sistema y caché desactivada.
Cronet se integra en la APK para funcionar sin descargar un proveedor desde
Google Play Services. El error móvil distingue ahora fallos de DNS, TLS y
conexión. Queda confirmar en el teléfono si esta ruta elimina la necesidad de
VPN; el éxito de Chrome por sí solo no prueba el resultado de la APK.

### Se publican dos APK, y hay que saber por qué

| Archivo | Tamaño | Para quién |
|---|---|---|
| `sivap-<v>-arm64.apk` | ~23 MB | El recomendado. Vale para prácticamente cualquier teléfono de los últimos años |
| `sivap-<v>-universal.apk` | ~65 MB | Solo si el anterior dice «no se instaló la aplicación» |

El universal lleva las bibliotecas nativas de las tres arquitecturas. A la
velocidad de conexión del equipo, la diferencia son veinte minutos por teléfono
—y hay nueve investigadores—. La página ofrece el de arm64 y solo enseña el
universal si hace falta.

### Dos cosas que aprendimos publicando la primera versión

La página pide la lista de releases y toma la primera con APK. La versión 0.2.0
usa el almacén cifrado de producción, exige el llavero del estudio y se
distribuye como prerelease de pruebas operativas con captura real bloqueada.

**El `if` de un paso no ve su propio `env`.** El paso de firma llevaba
`if: env.LLAVERO != ''` con `LLAVERO` definido en el mismo paso, así que se
saltaba siempre — incluso con el secreto configurado. Ahora la comprobación va
en un paso aparte.

## Antecedentes de la decisión

El repositorio es **público** (Telestas/SIVAP), así que:

- GitHub Pages funciona: la página está en **https://telestas.github.io/SIVAP/**
- Los archivos de las releases se descargan **sin autenticación**, que es lo que
  hacía falta para que el equipo médico pueda instalar la app sin cuenta de GitHub.

Un apunte que conviene no perder de vista: **GitHub Packages no admite APKs.** Ese
registro solo acepta npm, Maven, NuGet, RubyGems, Gradle y contenedores. Para un
binario suelto lo que corresponde son las **releases**, y así está montado
`apk.yml`.

La contrapartida de ser público es que no hay red de seguridad: lo que se sube se ve
al instante y no se puede despublicar. De ahí la restricción 15 de CLAUDE.md — nada
identificable entra al repositorio.

## La firma del APK: decidir antes de repartir nada

`apk.yml` firma con el llavero del estudio si están **los cuatro** secretos:

| Secreto | Contenido |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | El archivo `.jks` codificado en base64, **sin saltos de línea** |
| `ANDROID_KEYSTORE_PASSWORD` | Contraseña del llavero |
| `ANDROID_KEY_ALIAS` | Alias de la clave |
| `ANDROID_KEY_PASSWORD` | Contraseña de la clave |

Van juntos o no va ninguno: si el llavero está pero falta la contraseña, la
compilación **se corta**. Continuar publicaría un APK con la clave de
depuración mientras el equipo cree que lleva la del estudio, y ese equívoco solo
se descubre el día que hace falta actualizar la app — cuando ya es tarde.

Tras firmar, el pipeline comprueba que el certificado resultante no es el de
depuración. Un APK mal firmado se instala igual: sin esa comprobación, nadie lo
notaría.

Para añadirlos sin que la clave pase por el portapapeles ni por el historial del
intérprete de comandos:

```bash
base64 -w0 sivap.jks | gh secret set ANDROID_KEYSTORE_BASE64 --repo Telestas/SIVAP
gh secret set ANDROID_KEYSTORE_PASSWORD --repo Telestas/SIVAP   # la pide por teclado
gh secret set ANDROID_KEY_ALIAS         --repo Telestas/SIVAP
gh secret set ANDROID_KEY_PASSWORD      --repo Telestas/SIVAP
```

El `-w0` de `base64` es lo que evita los saltos de línea. Con ellos, el
`base64 -d` del pipeline falla con un error que no dice lo que pasa.

Si no están los cuatro, la publicación de producción se detiene. Una APK de
desarrollo puede instalarse para revisar la interfaz, pero no debe capturar
datos reales porque al cambiar la firma se perdería el acceso a la base local.

> El día que se pase a una clave propia, Android tratará la app como una
> **aplicación distinta**. Cada usuario tendrá que desinstalar la anterior. Y
> al desinstalar se borra la clave de cifrado del Keystore del dispositivo, y
> con ella **todo lo capturado que no se hubiera sincronizado**.

**Cree y custodie el llavero antes de capturar un solo dato real.**

```bash
keytool -genkey -v -keystore sivap.jks -keyalg RSA -keysize 4096 \
  -validity 10000 -alias sivap
base64 -w0 sivap.jks   # esto es lo que va en ANDROID_KEYSTORE_BASE64
```

El archivo `sivap.jks` y sus contraseñas hay que guardarlos donde no se
pierdan. **Si se pierde el llavero, no se puede volver a publicar una
actualización de la app**: habría que repartir una aplicación nueva y los
usuarios perderían los datos locales. No es recuperable de ninguna manera.

## El identificador de aplicación

Es `cu.sivap.sivap`, fijado con `--org cu.sivap` en los workflows. Cambiarlo
tiene exactamente las mismas consecuencias que cambiar la clave de firma: para
Android sería otra aplicación. Conviene darlo por bueno ahora o cambiarlo antes
de la primera entrega, no después.

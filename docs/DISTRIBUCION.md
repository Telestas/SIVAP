# Distribución del APK

## Estado: funcionando

**https://telestas.github.io/SIVAP/** — la página lee la última versión
publicada y ofrece el APK. Comprobado que se descarga sin cuenta de GitHub.

## Prueba del flujo sin Firebase

En el acceso de la app, **Probar flujo sin conexión** abre una sesión separada
con datos ficticios. Permite enrolar, guardar, registrar un consentimiento de
prueba y capturar eventos. Usa una secuencia ficticia ya generada. Todo queda en
memoria, no se sincroniza y se borra al salir de la prueba. Nunca introducir
datos de pacientes reales en esta sesión.

En la sesión del estudio, **Solicitar tramo** pide al servicio una reserva
exclusiva de posiciones de la secuencia A/B para este dispositivo. La función
remota aún no está publicada, por lo que el enrolamiento real sigue bloqueado.
Tampoco se sustituye por una asignación local improvisada.

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
ese HTML 403 en una sesión válida. Hasta contar con un backend aprobado y
accesible, el acceso real requiere una ruta de red que alcance los servicios
de Firebase. La prueba local descrita arriba funciona sin esa ruta.

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

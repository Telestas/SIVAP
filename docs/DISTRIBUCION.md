# Distribución del APK

## Estado: funcionando

**https://telestas.github.io/SIVAP/** — la página lee la última versión
publicada y ofrece el APK. Comprobado que se descarga sin cuenta de GitHub.

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

**`/releases/latest` no sirve aquí.** Excluye las prereleases, y mientras el CEI
no apruebe el estudio todas las versiones lo son. La página pide la lista
completa y toma la primera.

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

`apk.yml` firma con el llavero del estudio si están estos secretos:

| Secreto | Contenido |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | El archivo `.jks` codificado en base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Contraseña del llavero |
| `ANDROID_KEY_ALIAS` | Alias de la clave |
| `ANDROID_KEY_PASSWORD` | Contraseña de la clave |

Si no están, el APK sale firmado con la clave de depuración que genera Flutter.
Se instala igual, y para enseñar la app es suficiente. Pero:

> El día que se pase a una clave propia, Android tratará la app como una
> **aplicación distinta**. Cada usuario tendrá que desinstalar la anterior. Y
> al desinstalar se borra la clave de cifrado del Keystore del dispositivo, y
> con ella **todo lo capturado que no se hubiera sincronizado**.

Como todavía no hay sincronización, hoy eso significaría perderlo todo. La
conclusión práctica es sencilla: **crear el llavero antes de que nadie capture
un solo dato real.**

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

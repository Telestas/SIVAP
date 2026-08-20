# Distribución del APK

## El problema que hay que resolver primero

Dos hechos que condicionan todo lo demás:

1. **GitHub Packages no admite APKs.** Ese registro solo acepta npm, Maven,
   NuGet, RubyGems, Gradle y contenedores. Para un binario suelto lo que
   corresponde son las **releases** del repositorio, y así está montado el
   workflow `apk.yml`.
2. **SIVAP es un repositorio privado.** Eso implica dos cosas a la vez:
   - GitHub Pages no está disponible para repositorios privados en el plan
     gratuito.
   - Los archivos de una release privada **no se pueden descargar sin
     autenticación**. Una página pública con un botón que apunte a una release
     privada devolvería un 404 a cualquiera que no tenga acceso al repositorio.

Es decir: **si se quiere un enlace de descarga público, el APK tiene que vivir
en un repositorio público.** No hay forma de rodearlo.

## Las tres salidas

### A. Repositorio público solo para distribución (recomendada)

Un segundo repositorio, por ejemplo `AlecoG/sivap-descargas`, **público**, que
contenga únicamente la página de descarga y las releases con el APK. El código,
los documentos del estudio y los nombres del equipo siguen en el repositorio
privado.

- El equipo médico recibe un enlace y descarga sin cuenta de GitHub.
- Nada del protocolo, del consentimiento ni de la identidad del equipo se hace
  público. Solo el APK y una página.
- Hay que asumir que el APK es descargable por cualquiera. En modo
  demostración eso no expone datos —los pacientes son inventados— pero conviene
  revisarlo antes de cada publicación.

Montaje: `apk.yml` publica la release en el repositorio público usando un token
con permiso sobre él, guardado como secreto.

### B. Todo privado, sin página

El APK se publica como release del repositorio privado. Lo descarga alguien con
acceso y lo reparte por USB, Bluetooth o red local del hospital.

- No hay que crear ni exponer nada.
- Para 4–10 investigadores es perfectamente viable.
- Cada actualización hay que repartirla a mano.

Es la opción que funciona **hoy**, sin decidir nada más.

### C. Plan de pago de GitHub

Con GitHub Pro, Pages funciona en repositorios privados. **No resuelve el
problema**: la página se publicaría, pero el enlace al APK seguiría exigiendo
autenticación. Solo tiene sentido si la página es de uso interno y quienes la
abren tienen cuenta con acceso al repositorio.

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

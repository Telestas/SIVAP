# deploy

Borrador del despliegue. Levanta hoy la base de datos y el panel web; el
servicio `api` está descrito pero el backend aún no existe (ver
[../docs/PENDIENTE.md](../docs/PENDIENTE.md)).

## Poner en marcha

```bash
cd deploy
cp .env.example .env                              # y rellenar las contraseñas
./tls/generar-certificado.sh sivap.hospital.local # certificado, una sola vez
docker compose up -d                              # base + panel web
```

El panel queda en `https://` + lo que hayas puesto en `SIVAP_DOMINIO`.

Cuando exista el backend, en `deploy/api/` con su `Dockerfile`:

```bash
docker compose --profile completo up -d
```

## El certificado

En una red de hospital no suele haber dominio público ni acceso a Let's
Encrypt, así que el certificado se genera con una autoridad propia del estudio.
`tls/generar-certificado.sh` la crea y firma con ella el certificado del
servidor. Detalle en [tls/README.md](tls/README.md).

**Cada dispositivo que abra el panel tiene que instalar `tls/ca.crt` una vez**,
o el navegador avisará de sitio no seguro. Es el precio de no tener dominio
público, y lo pagaría igual cualquier otro servidor web.

Dos cosas que hay que tener presentes y que no avisan solas:

- El certificado del servidor **caduca al año**. Cuando pase, el panel deja de
  abrir. Renovarlo es volver a correr el guion, que reutiliza la autoridad —así
  que no hay que reinstalar nada en los dispositivos— y recrear el contenedor.
- `tls/ca.key` es la clave de la autoridad del estudio. **No sale del
  servidor.** Quien la tenga puede emitir certificados válidos para cualquier
  dispositivo donde se haya instalado `ca.crt`.

Si el servidor sí llega a tener nombre público y los puertos 80 y 443 abiertos,
lo correcto es pasar a Let's Encrypt (con certbot o acme.sh): certificado
reconocido por todos los navegadores, sin instalar nada en los dispositivos, y
renovación automática.

## Advertencia sobre el panel web

El panel web **no guarda nada localmente y no puede cifrar nada en el
navegador**: en web no hay archivo de base de datos que cifrar, y una clave
guardada en el propio navegador no protege de nadie. Por eso el panel está
pensado para leer del servidor, no para capturar datos en el navegador.

La captura de datos en sala se hace en la app móvil, que sí tiene base local
cifrada. Mientras el backend no exista, el panel web arranca con datos en
memoria y lo dice en pantalla.

## Copias de seguridad

El volumen `datos_postgres` es el estudio entero. `./copias` está montado
dentro del contenedor de la base para poder volcar ahí:

```bash
docker compose exec db pg_dump -U sivap sivap | gzip > copias/sivap-$(date +%F).sql.gz
```

Una copia que se queda en el mismo servidor que el original no es una copia de
seguridad. Hay que sacarla de la máquina.

Cuidado: ese volcado contiene nombres, carnés de identidad y datos clínicos.
Cifrarlo antes de moverlo a ningún sitio.

## Lo que falta en este borrador

- El `Dockerfile` de la api, cuando exista el backend.
- Renovación del certificado sin intervención manual (hoy hay que acordarse).
- Migraciones de la base en el arranque de la api.
- Copias de seguridad automáticas, en vez del comando manual de arriba.
- Límites de recursos por contenedor.
- Comprobar la compilación web: `flutter build web` no se ha ejecutado nunca en
  este proyecto todavía.

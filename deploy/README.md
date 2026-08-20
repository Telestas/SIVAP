# deploy

Borrador del despliegue. Levanta hoy la base de datos y el panel web; el
servicio `api` está descrito pero el backend aún no existe (ver
[../docs/PENDIENTE.md](../docs/PENDIENTE.md)).

## Poner en marcha

```bash
cd deploy
cp .env.example .env      # y rellenar las tres contraseñas
docker compose up -d      # base + panel web
```

El panel queda en `https://` + lo que hayas puesto en `SIVAP_DOMINIO`.

Cuando exista el backend, en `deploy/api/` con su `Dockerfile`:

```bash
docker compose --profile completo up -d
```

## El certificado

Caddy emite el certificado con su propia autoridad (`tls internal`), porque en
una red de hospital normalmente no hay dominio público ni acceso a Let's
Encrypt. **Cada dispositivo que abra el panel tiene que instalar esa autoridad
una vez**, o el navegador avisará de sitio no seguro:

```bash
docker compose cp web:/data/caddy/pki/authorities/local/root.crt ./sivap-ca.crt
```

Ese archivo se instala como certificado raíz de confianza en cada equipo o
teléfono. Está en el volumen `datos_caddy`: si se borra ese volumen, Caddy
genera una autoridad nueva y hay que repetir la instalación en todas partes.

Si el servidor sí tiene nombre público y los puertos 80 y 443 abiertos desde
internet, quitar `tls internal` del `Caddyfile` y Caddy pedirá un certificado
real solo. Es preferible, si es posible.

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
- Migraciones de la base en el arranque de la api.
- Copias de seguridad automáticas, en vez del comando manual de arriba.
- Límites de recursos por contenedor.
- Comprobar la compilación web: `flutter build web` no se ha ejecutado nunca en
  este proyecto todavía.

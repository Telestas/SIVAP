# Compilación web de SIVAP servida por nginx.
#
# El contexto de build es la raíz del repositorio (ver compose.yaml), para que
# esta imagen pueda leer `app/`.

# ── Etapa 1: compilar ────────────────────────────────────────────────
FROM debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.47.1

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

# El SDK son ~1,5 GB. En una conexión lenta esta capa tarda, pero se cachea:
# solo se vuelve a descargar si cambia FLUTTER_VERSION.
RUN curl -fsSL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && tar -xf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz
ENV PATH="/opt/flutter/bin:${PATH}"

# Flutter se niega a operar sobre un repositorio git de otro usuario.
RUN git config --global --add safe.directory /opt/flutter \
    && flutter --version

WORKDIR /src

# Primero solo el manifiesto: así `pub get` se cachea y no se repite en cada
# cambio de código.
COPY app/pubspec.yaml app/pubspec.lock* ./
RUN flutter pub get || true

COPY app/ ./

# `flutter create` genera el andamiaje de la plataforma web si no está en el
# repositorio. Es idempotente y no toca lib/ ni test/.
RUN flutter create --platforms=web . \
    && flutter pub get \
    && flutter build web --release

# ── Etapa 2: servir ──────────────────────────────────────────────────
FROM nginx:1.27-alpine

COPY --from=build /src/build/web /srv/sivap

# nginx sustituye las variables de las plantillas de este directorio al
# arrancar, y deja el resultado en /etc/nginx/conf.d/.
COPY deploy/web/nginx.conf.template /etc/nginx/templates/sivap.conf.template

# La configuración por defecto sirve su propia página en el puerto 80 y
# chocaría con la nuestra.
RUN rm -f /etc/nginx/conf.d/default.conf

EXPOSE 80 443

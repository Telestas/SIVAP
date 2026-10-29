#!/usr/bin/env bash
# Copia los archivos necesarios para Cloudflare Pages. Flutter usa CanvasKit
# desde gstatic.com; sus copias locales y los símbolos no se usan en esta web.
set -euo pipefail
cd "$(dirname "$0")/.."

test -f build/web/index.html
test -f build/web/firebase_proxy.js
test -f build/web/_routes.json
test -f build/web/_headers
test -f build/web/_redirects

mkdir -p build/pages
rsync -a --delete \
  --exclude='canvaskit/' \
  --exclude='*.symbols' \
  build/web/ build/pages/

test -f build/pages/main.dart.js
test -f build/pages/firebase_proxy.js
test -f build/pages/_routes.json
test -f build/pages/_headers
test -f build/pages/_redirects
mkdir -p build/pages/descargar
cp ../web-descarga/index.html build/pages/descargar/index.html
cp ../web-descarga/logo.png ../web-descarga/icono.png build/pages/descargar/
cp -r ../web-descarga/fonts build/pages/descargar/
sed -i 's|__REPO__|Telestas/SIVAP|g' build/pages/descargar/index.html
test -f build/pages/descargar/index.html
echo 'Web preparada para Cloudflare Pages en app/build/pages.'

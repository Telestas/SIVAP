#!/usr/bin/env bash
# Copia los archivos necesarios para Cloudflare Pages. Flutter usa CanvasKit
# desde gstatic.com; sus copias locales y los símbolos no se usan en esta web.
set -euo pipefail
cd "$(dirname "$0")/.."

test -f build/web/index.html
test -f build/web/firebase_proxy.js
test -f build/web/_routes.json
test -f build/web/_headers

mkdir -p build/pages
rsync -a --delete \
  --exclude='canvaskit/' \
  --exclude='*.symbols' \
  build/web/ build/pages/

test -f build/pages/main.dart.js
test -f build/pages/firebase_proxy.js
test -f build/pages/_routes.json
test -f build/pages/_headers
echo 'Web preparada para Cloudflare Pages en app/build/pages.'

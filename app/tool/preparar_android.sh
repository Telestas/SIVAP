#!/usr/bin/env bash
#
# Genera el andamiaje de plataforma y le aplica encima lo que sí versionamos.
#
#   tool/preparar_android.sh [plataformas]     (por defecto: android)
#
# El andamiaje —`android/`, `web/`— no está en el repositorio: lo regenera
# Flutter en cada compilación. Eso mantiene el repositorio limpio, pero implica
# que cualquier cosa que se edite ahí dentro se pierde en la siguiente. Los
# iconos y el nombre de la app son exactamente eso, así que viven fuera y se
# copian aquí.

set -euo pipefail
cd "$(dirname "$0")/.."

PLATAFORMAS="${1:-android}"

flutter create --platforms="$PLATAFORMAS" --org cu.sivap .

# `flutter create` añade su test de ejemplo, que referencia una clase MyApp que
# este proyecto no tiene.
rm -f test/widget_test.dart

if [[ "$PLATAFORMAS" == *android* ]]; then
  # Iconos: clásico, capas del adaptativo, monocromo y color de fondo.
  cp -r android_res/. android/app/src/main/res/

  # El nombre bajo el icono. `flutter create` pone el nombre del proyecto tal
  # cual, en minúsculas.
  sed -i 's/android:label="sivap"/android:label="SIVAP"/' \
    android/app/src/main/AndroidManifest.xml

  # Si Flutter cambia su plantilla y alguno de los reemplazos deja de encajar,
  # mejor que falle aquí que descubrirlo con la app ya repartida, llamándose
  # «sivap» y con el icono azul de Flutter.
  grep -q 'android:label="SIVAP"' android/app/src/main/AndroidManifest.xml
  test -f android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
  test -f android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml

  echo 'Andamiaje de Android preparado: iconos y nombre aplicados.'
fi

if [[ "$PLATAFORMAS" == *web* ]]; then
  # La plantilla de Flutter trae su propio favicon e iconos PWA. Se reemplazan
  # en cada build porque web/ se regenera y no se versiona.
  cp assets/icono/sivap_icon_rounded_512.png web/favicon.png
  cp assets/icono/sivap_icon_rounded_512.png web/favicon-sivap.png
  cp android_res/mipmap-xxxhdpi/ic_launcher.png web/icons/Icon-192.png
  cp assets/icono/sivap_icon_rounded_512.png web/icons/Icon-512.png
  cp android_res/mipmap-xxxhdpi/ic_launcher.png \
    web/icons/Icon-maskable-192.png
  cp assets/icono/sivap_icon_rounded_512.png web/icons/Icon-maskable-512.png

  sed -i \
    -e 's/A new Flutter project\./SIVAP · captura clínica offline-first./' \
    -e 's/apple-mobile-web-app-title" content="sivap"/apple-mobile-web-app-title" content="SIVAP"/' \
    -e 's/href="favicon.png"/href="favicon-sivap.png"/' \
    -e 's/<title>sivap<\/title>/<title>SIVAP<\/title>/' \
    web/index.html
  sed -i \
    -e 's/"name": "sivap"/"name": "SIVAP"/' \
    -e 's/"short_name": "sivap"/"short_name": "SIVAP"/' \
    -e 's/"background_color": "#0175C2"/"background_color": "#16181A"/' \
    -e 's/"theme_color": "#0175C2"/"theme_color": "#16181A"/' \
    -e 's/"description": "A new Flutter project\."/"description": "SIVAP · captura clínica offline-first."/' \
    web/manifest.json

  grep -q '<title>SIVAP</title>' web/index.html
  grep -q 'href="favicon-sivap.png"' web/index.html
  grep -q '"name": "SIVAP"' web/manifest.json
  test -f web/favicon-sivap.png
  test -f web/icons/Icon-512.png

  echo 'Andamiaje web preparado: iconos, nombre y colores aplicados.'
fi

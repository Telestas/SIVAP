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

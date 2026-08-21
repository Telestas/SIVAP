#!/usr/bin/env python3
"""Genera los iconos de Android a partir de los archivos de diseño.

    python3 tool/generar_iconos.py

Lee `assets/icono/` y escribe `android_res/`, que el pipeline copia sobre el
andamiaje que genera `flutter create`. Ese andamiaje no se versiona —se
regenera en cada compilación—, así que los iconos tienen que vivir fuera de él
o se perderían en la siguiente.

No se usa `flutter_launcher_icons`, que es lo que recomienda la entrega de
diseño, por dos razones: añade una dependencia y un paso de generación de
código, y este proyecto no tiene ninguno de los dos (ver CLAUDE.md). El
redimensionado es todo lo que hace falta y cabe en este archivo.

Para cambiar el icono: sustituir los archivos de `assets/icono/` y volver a
ejecutar esto.

Requiere Pillow:  pip install Pillow
"""

from pathlib import Path

from PIL import Image

RAIZ = Path(__file__).resolve().parent.parent
ORIGEN = RAIZ / 'assets' / 'icono'
SALIDA = RAIZ / 'android_res'

# Fondo del icono adaptativo. Va como color plano y no como imagen: pesa menos
# y es lo que indica la entrega de diseño.
FONDO = '#16181A'

# El icono clásico se sirve del maestro con esquinas ya redondeadas: los
# teléfonos que no aplican máscara propia lo pintan tal cual, y un cuadrado a
# sangre se vería como un cuadrado.
CLASICO = ORIGEN / 'sivap_icon_rounded_512.png'

# Las capas del icono adaptativo. Android compone fondo y primer plano y les
# aplica la máscara del fabricante; la monocroma es para los iconos temáticos
# de Android 13 en adelante.
PRIMER_PLANO = ORIGEN / 'android_foreground_432.png'
MONOCROMO = ORIGEN / 'android_monochrome_432.png'

# Tamaños en píxeles por densidad. El icono clásico va a 48 dp; las capas del
# adaptativo, a 108 dp, porque el sistema les recorta los bordes al aplicar la
# máscara: solo el 66 % central está garantizado.
DENSIDADES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def escalar(origen: Path, lado: int) -> Image.Image:
    return Image.open(origen).convert('RGBA').resize(
        (lado, lado), Image.LANCZOS)


def main() -> None:
    for archivo in (CLASICO, PRIMER_PLANO, MONOCROMO):
        if not archivo.exists():
            raise SystemExit(f'Falta el archivo de diseño: {archivo}')

    for densidad, factor in DENSIDADES.items():
        carpeta = SALIDA / f'mipmap-{densidad}'
        carpeta.mkdir(parents=True, exist_ok=True)

        escalar(CLASICO, int(48 * factor)).save(carpeta / 'ic_launcher.png')
        escalar(PRIMER_PLANO, int(108 * factor)).save(
            carpeta / 'ic_launcher_foreground.png')
        escalar(MONOCROMO, int(108 * factor)).save(
            carpeta / 'ic_launcher_monochrome.png')

    anydpi = SALIDA / 'mipmap-anydpi-v26'
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / 'ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/fondo_icono" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n')

    valores = SALIDA / 'values'
    valores.mkdir(parents=True, exist_ok=True)
    (valores / 'colores.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <!-- Fondo del icono, según la entrega de diseño. -->\n'
        f'    <color name="fondo_icono">{FONDO}</color>\n'
        '</resources>\n')

    total = sum(1 for f in SALIDA.rglob('*') if f.is_file())
    print(f'{total} archivos escritos en {SALIDA.relative_to(RAIZ)}/')


if __name__ == '__main__':
    main()

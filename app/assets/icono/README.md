# Icono de la aplicación

Cruz clínica sobre fondo carbón. La barra vertical está partida en los dos
colores de rama del ensayo y la horizontal es la superficie clara de la app.

> **Vocabulario corregido respecto a la entrega original.** El documento de
> diseño describía las mitades como «protocolo nuevo» y «protocolo vigente»,
> que es el modelo anterior al reencaminamiento. El sistema solo conoce
> **Protocolo A** y **Protocolo B** (CLAUDE.md §2). Los colores no cambian —son
> los mismos de los distintivos A/B de la app—, solo el nombre con el que se
> describen.
>
> El icono en sí no rompe el cegamiento: un par de colores no dice cuál rama es
> LIVERE. Lo que había que quitar era la frase que sí lo decía.

## Colores

| Uso | Hex |
|---|---|
| Fondo | `#16181A` |
| Rama A (mitad superior) | `#3F9C92` |
| Rama B (mitad inferior) | `#5B86C4` |
| Barra horizontal | `#FBFBFA` |

## Geometría (proporciones del lado del icono)

- Largo de cada brazo: **62,1 %**
- Grosor de cada brazo: **19,7 %**
- Radio de las esquinas de los brazos: **11,5 % del grosor**
- Cruz centrada, sin relleno óptico adicional.
- En la variante adaptativa el brazo se reduce a **40 %** de largo y **12,7 %**
  de grosor, para caber en la zona segura central del 66 %.

## Archivos

| Archivo | Uso |
|---|---|
| `sivap_icon.svg` | Fuente vectorial, 1024×1024. Es el original |
| `sivap_icon_1024.png` | Maestro a sangre, sin esquinas redondeadas |
| `sivap_icon_rounded_512.png` | Con esquinas redondeadas: icono clásico de Android, favicon y documentos |
| `android_foreground_432.png` | Capa de primer plano del icono adaptativo |
| `android_monochrome_432.png` | Capa monocroma, para los iconos temáticos de Android 13+ |

## Cómo se integran

```bash
cd app
python3 tool/generar_iconos.py     # requiere Pillow
```

Escribe `app/android_res/`, que `tool/preparar_android.sh` copia sobre el
andamiaje después de `flutter create`. Ese andamiaje no se versiona: se
regenera en cada compilación, y cualquier cosa editada dentro se perdería.

**No se usa `flutter_launcher_icons`**, que es lo que recomendaba la entrega de
diseño. Añadiría una dependencia y un paso de generación de código, y este
proyecto no tiene ninguno de los dos a propósito. Lo único que hace falta es
redimensionar, y eso cabe en `tool/generar_iconos.py`.

Para cambiar el icono: sustituir estos archivos y volver a ejecutar el guion.

## Reglas de uso

- No recolorear la cruz ni invertir el orden de las mitades: el verde azulado
  arriba y el azul abajo repiten el código de color de los distintivos A/B
  dentro de la app.
- Sin sombras, degradados ni texto.
- Sobre fondos claros, `sivap_icon_rounded_512.png`. Nunca la cruz sin su fondo
  carbón.
- Área de respeto en documentos: 12 % del lado del icono.

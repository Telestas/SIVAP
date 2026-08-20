# Hito 1 — Interfaz y capa de datos local

Estado: **para revisión del equipo**. Fecha: 20 ago 2026.

## Qué se entrega

Las siete pantallas del diseño de Claude Design implementadas en Flutter, sobre
una capa de datos local con datos de demostración. Se puede recorrer la app
entera: entrar con cada uno de los tres roles, enrolar un paciente, firmar el
consentimiento, capturar una visita, cerrarla, y ver la corrección con auditoría
desde el panel de administración.

## Qué hay que mirar en la revisión

0. **La semilla y la longitud de la secuencia.** Antes de enrolar al primer
   paciente real, el investigador principal tiene que fijar ambas y dejarlas en
   el acta del estudio. Hasta entonces la app usa una semilla de demostración.

1. **Los campos de visita** (pantalla 05). Son los de la maqueta, no los
   definitivos. Es la decisión pendiente más bloqueante: hasta que el equipo
   médico entregue el listado real por visita, el dataset exportable no queda
   fijado. Cambiarlos no requiere tocar código de pantalla, solo la definición.
2. **Los rangos clínicos**. La app avisa cuando un valor sale de rango pero no
   lo impide — un 38.7 °C real tiene que poder registrarse. Confirmar que ese
   criterio es el correcto y revisar los límites concretos.
3. **El vocabulario**. "Protocolo vigente / protocolo nuevo", "recolector de
   campo", "visita perdida". Si el equipo usa otras palabras, cambiarlas ahora
   es barato.
4. **El flujo de corrección**. Un administrador toca un campo de una visita ya
   enviada, escribe el motivo, y queda en el historial. Verificar que el motivo
   obligatorio no estorba en la práctica real del servicio.

## Decisiones tomadas en este hito

- **Aleatorización simple generada por computadora, desde semilla registrada**
  (decisión del equipo, 20 ago 2026 — ver BASES §6). La secuencia completa se
  genera antes del primer paciente como un código binario (`0` = vigente,
  `1` = nuevo) y se consume en orden. La semilla queda registrada porque es lo
  que hace la aleatorización auditable: con ella se regenera la misma secuencia
  y se verifica que cada asignación fue la que tocaba. La app no sortea nada en
  el momento de enrolar.
- **La rama se asigna al guardar la ficha**, no al abrir el formulario. Si se
  asignara al abrir, un formulario abandonado dejaría un hueco sin paciente en
  la secuencia del bioestadista.
- **Sin dependencias de terceros.** La app se compila solo con el SDK. Cuando
  entre la persistencia cifrada habrá que resolver el acceso a pub.dev una vez.
- **El administrador usa el panel de escritorio** en pantallas de 900 px o más;
  en móvil recibe la lista de campo, para no dejarlo sin app en el teléfono.

## Lo que sigue (Hito 2, propuesta)

1. Persistencia local **cifrada** (Drift o Isar) sustituyendo el almacén en
   memoria. La interfaz `StudyRepository` ya está, no cambia ninguna pantalla.
2. Backend FastAPI: autenticación por rol, endpoints de ficha/visita/auditoría.
3. Cola de sincronización real y resolución de conflictos.
4. Exportación .xlsx con ficha y datos clínicos por separado.

Los puntos 2 y 3 dependen de tener servidor donde desplegar; el 1 no depende de
nada externo y es el que más reduce riesgo.

## Limitación conocida de este entorno

El código **no se pudo compilar ni ejecutar** al escribirlo: la descarga del SDK
de Flutter (1,57 GB) no completó por ancho de banda. Está revisado a mano pero
no verificado por el compilador. Lo primero que debe hacer quien tenga Flutter
instalado:

```bash
cd app && flutter pub get && flutter analyze && flutter test
```

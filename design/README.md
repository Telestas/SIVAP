# design

`SIVAP.dc.html` es el canvas de Claude Design del que sale la interfaz, traído
tal cual desde el proyecto:

https://claude.ai/design/p/3ab9bcdc-4ee8-4651-a806-a073aa3040d2

Siete artboards: acceso, lista del recolector, lista del observador,
enrolamiento, captura de visita, consentimiento y panel de administración.

Se versiona como **referencia**, no como código: no forma parte de la app ni se
compila. Si el diseño cambia en el canvas, se vuelve a traer este archivo y se
ajusta la app contra él. Los valores de color y tipografía que usa la app están
extraídos de aquí a `app/lib/core/theme/tokens.dart`.

El canvas depende de un `support.js` (el motor del editor de Claude Design) que
no se versiona: abrir este archivo suelto en un navegador no lo renderiza. Para
verlo, usar el enlace de arriba.

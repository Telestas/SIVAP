# Firebase: backend de consolidación

Este directorio define el despliegue de Firebase del proyecto `sivap-f5060`.
La app móvil conserva SQLite cifrado y la cola local; Firestore solo recibe una
copia confirmada durante la sincronización. GitHub Pages sigue publicando la
página de descarga del APK. Firebase Hosting, si se activa, sirve únicamente el
panel web compilado en `app/build/web`.

## Estado y límites

No cree datos clínicos ni habilite enrolamiento real hasta que estén aprobados el
CEI, la custodia de datos y la política de aleatorización. Las reglas no permiten
la colección de secuencias ni tramos: una app cliente no puede repartirlos sin
exponer o manipular la siguiente asignación. `Protocolo A` y `Protocolo B` son las
únicas etiquetas admitidas en los datos del estudio.

La región seleccionada es `nam5` (multirregión de Estados Unidos central), para
priorizar disponibilidad y durabilidad. Esa elección será permanente al crear la
base; documente su aprobación institucional fuera del repositorio. Inicialice la
base en modo producción, nunca en modo de prueba.

## Operación

Los perfiles se aprovisionan desde una herramienta administrativa confiable; la
app no puede crear usuarios, elevar roles ni cambiar instituciones. Cada perfil
debe contener `institucion_codigo` y `roles`. Las reglas requieren además que
cada documento sincronizado incluya `institucion_codigo` y `autor_uid`.

Tras crear la base y probar las reglas con Emulator Suite:

```bash
firebase deploy --only firestore
firebase deploy --only hosting
```

No guarde cuentas de servicio, tokens de CI ni archivos de configuración privados
en el repositorio. Las reglas son código: todo cambio requiere pruebas de permisos
antes de desplegarlo.

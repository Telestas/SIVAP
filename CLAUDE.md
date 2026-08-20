# CLAUDE.md — Constitución del repositorio

Reglas permanentes del proyecto. Cualquier sesión de Claude Code las lee antes de
generar o modificar código. No se negocian salvo decisión explícita del equipo,
documentada aquí.

> **Revisión del 20 ago 2026.** Reescrito tras leer el protocolo LIVERE, el proyecto
> de investigación y el Anexo 4. La versión anterior describía un estudio de cohorte
> con visitas en días fijos: era una suposición de trabajo, y era incorrecta. El
> código existente que asume ese modelo no está mal escrito — se escribió contra las
> bases anteriores. Ver `docs/REENCAMINAMIENTO.md`.

> **Repositorio público.** Nada de lo que se escriba aquí debe identificar a personas.
> Sin nombres de investigadores, sin nombres de centros, sin datos de pacientes. Esa
> información vive en el expediente del estudio, no en el control de versiones. Un
> repositorio público no se puede despublicar: lo que se sube, se subió.

---

## Qué es este proyecto

Sistema (app Flutter móvil + web, backend FastAPI + PostgreSQL) para conducir y
registrar el **ensayo clínico LIVERE**: validación de un protocolo de liberación de
la ventilación mecánica invasiva en unidades de cuidados intensivos, en entornos de
recursos limitados.

- **Diseño**: ensayo clínico **controlado, aleatorizado, multicéntrico, prospectivo
  y longitudinal**. No es un estudio de cohorte.
- **Centros**: tres, en La Habana — un hospital clínico-quirúrgico docente
  (coordinador), un instituto de cardiología y cirugía cardiovascular, y un hospital
  militar central. La lista nominal vive en el expediente del estudio, no aquí.
- **Conducción**: a cargo de la investigadora principal, que se nombra por su rol en
  todo el sistema y en toda la documentación.
- **Duración prevista**: 12 meses, con 6 meses de fase de intervención.
- **Hipótesis**: la aplicación del protocolo LIVERE reduce la tasa de extubación
  fallida y mejora desenlaces clínicos frente al manejo convencional.
- **Seguimiento**: desde la aplicación del protocolo hasta 28 días posteriores al
  egreso de UCI, o hasta evento terminal previo.

Alcance detallado en `BASES_MVP_SIVAP.md`.

---

## Glosario del dominio

**Del ensayo**

- **Rama / brazo**: Protocolo A o Protocolo B. Una es LIVERE, la otra el manejo
  convencional. **Cuál es cuál no se sabe dentro del sistema** (restricción 2).
- **Secuencia de asignación**: lista de ramas generada por computadora antes de
  enrolar al primer paciente, consumida en orden.
- **Descegamiento**: acto único, al cierre del estudio, en que se revela la
  correspondencia A/B → LIVERE/convencional. Ocurre fuera del sistema.
- **Ficha del paciente**: identidad y contacto. Se crea una sola vez.
- **Registro de evento clínico**: datos capturados en un hito del proceso. Entidad
  separada de la ficha, vinculada solo por ID interno.
- **Investigador**: usuario del sistema. Roles en BASES §4.

**Clínico** (necesario para no malinterpretar los campos)

- **VMI**: ventilación mecánica invasiva.
- **Liberación de la VMI**: todo el proceso, desde los primeros pasos para separar
  al paciente del ventilador hasta los cuidados respiratorios post-extubación.
- **Weaning / destete**: transición gradual del soporte completo a la ventilación
  espontánea.
- **PVE**: prueba de ventilación espontánea. **Puede repetirse** en un mismo paciente
  (1, 2, 3, 4 o más intentos). Cada intento registra monitorización al inicio y al
  final.
- **RSBI**: índice de respiración rápida superficial (índice de Tobin).
- **Extubación fallida**: necesidad de reintubación dentro de las 48–72 h posteriores
  al retiro del tubo endotraqueal. Desenlace principal del estudio.
- **Test de fuga**: prueba previa a la extubación, estima riesgo de estridor.
- **HFNC / VNI**: cánula nasal de alto flujo / ventilación no invasiva. Soporte
  post-extubación.
- **Traqueostomía**: si se realiza, cambia la trayectoria del paciente en el estudio.

---

## Restricciones permanentes (NO NEGOCIABLES)

**1. Separación ficha / datos clínicos.**
Identidad y datos clínicos viven en entidades separadas, vinculadas por un ID
interno. Nunca fusionar en un solo modelo o tabla por conveniencia. Esto permite
exportar el dataset clínico sin identidad.

**2. Cegamiento: el sistema no sabe cuál rama es LIVERE.**
App, backend y base de datos manejan exclusivamente **Protocolo A** y **Protocolo B**.
Está prohibido:
- nombrar las ramas "nuevo/vigente", "experimental/control" o "LIVERE/convencional"
  en modelos, columnas, etiquetas de interfaz, exportaciones o logs;
- almacenar en cualquier parte del sistema la correspondencia A/B → LIVERE/control;
- exponer contenido de protocolo que permita inferir cuál rama es cuál.

La correspondencia vive en el expediente del estudio en papel, en custodia de la
investigadora principal. El descegamiento ocurre fuera del sistema, una sola vez, al
cierre. Un ensayo cuyo cegamiento se rompe por la herramienta de captura pierde
validez interna: esto no es preferencia de diseño.

`test/cegamiento_test.dart` lo comprueba de forma automática. Si falla, no se relaja
la aserción: se corrige el código.

**3. Sin ediciones silenciosas.**
Ningún registro ya enviado se sobrescribe. Toda corrección genera entrada de
auditoría con valor anterior, valor nuevo, autor, fecha/hora y motivo. Aplica también
al rol de mayor privilegio. La tabla de auditoría es de solo inserción, protegida por
disparadores.

**4. La captura se estructura por eventos clínicos, no por calendario.**
No existen "visitas del día N". Existen hitos del proceso de liberación, que ocurren
cuando la clínica lo determina, y algunos se repiten un número indeterminado de veces
(cribado diario, intentos de PVE). Cualquier modelo que asuma un índice de día fijo o
una fecha programada de visita está mal planteado. Ver BASES §5.

Corolario: **un evento que no ocurrió no existe**. No se pre-crean calendarios ni se
marcan hitos como "perdidos"; los registros se crean cuando el hito sucede.

**5. Formularios definidos como datos, no como código.**
Los campos de cada evento se definen como estructura de datos (clave, tipo,
obligatoriedad, validación, opciones), servida por el backend. Ajustar el protocolo es
editar la definición, no recompilar la app. La `key` de cada campo es la columna del
dataset exportado: renombrar la etiqueta es cosmético, renombrar la clave rompe el
dataset.

**6. Módulo de asignación desacoplado, y ciego hacia adelante.**
La lógica que asigna rama vive en un componente aislado y reemplazable. Por defecto:
aleatorización simple, secuencia generada íntegra antes del primer enrolamiento y
consumida en orden. Prohibido:
- que el investigador elija la rama;
- exponer cuál rama toca a continuación sin consumirla (permitiría decidir a quién se
  enrola: sesgo de selección);
- sortear en el momento del enrolamiento (permitiría repetir el sorteo hasta obtener
  la rama preferida, sin dejar rastro).

**7. La semilla no vive en el repositorio ni en la app.**
Se genera una vez desde fuente aleatoria física o `/dev/urandom`, se anota en el
expediente en papel y la custodia la investigadora principal. Al sistema se carga la
secuencia, cifrada. La semilla sirve después, para verificación por revisor externo.
No debe ser una fecha ni nada adivinable. Longitud al menos el triple de la cohorte
prevista.

**8. Multicéntrico: todo registro lleva institución.**
Ficha de paciente, evento clínico y usuario declaran a qué centro pertenecen. Los
análisis por centro y el control de contaminación entre grupos dependen de esto.

**9. Minimización de datos personales.**
Solo se almacena lo que el formulario del estudio exige (Anexo 4): código de paciente
autogenerado, teléfonos de contacto, institución y las variables demográficas del
Módulo 1. Todo dato personal adicional es superficie de riesgo que hay que justificar
ante el Comité de Ética. Ante la duda, no se guarda.

**10. Cifrado obligatorio.**
Base local cifrada en reposo (SQLCipher, clave en Keystore/Keychain). Comunicación
siempre por TLS. Nunca contraseñas ni tokens en texto plano.

**11. Cada endpoint declara su rol.**
Ninguna ruta nueva sin declarar explícitamente qué rol puede invocarla. Ver la tabla
de roles en BASES §4, que refleja la separación de funciones exigida por el
cegamiento.

**12. Offline-first real.**
Toda captura opera sin conexión. La sincronización es proceso posterior, nunca
requisito para trabajar. El contexto energético y de conectividad en Cuba lo hace
requisito funcional, no optimización.

**13. Sin pacientes reales hasta la aprobación del CEI.**
El enrolamiento real queda tras un flag explícito de aprobación del Comité de Ética
de la Investigación de cada institución participante, gestionado como configuración
del estudio, no como código.

**14. El dato clínico manda sobre la validación.**
Los rangos de plausibilidad avisan, no bloquean. Un valor extremo real —y en UCI los
hay— debe poder registrarse. Bloquear la captura de un dato verdadero corrompe el
dataset más que admitir un tecleo erróneo, que la auditoría permite corregir.

**15. Nada identificable en el repositorio.**
El repositorio es público. No se versionan nombres de investigadores, nombres de
centros, datos de pacientes, semillas reales ni credenciales. Los datos de
demostración son inventados y están marcados como tales.

---

## Convenciones técnicas

- **Cliente**: Flutter (Dart), móvil y web desde el mismo código. Persistencia local
  SQLite + SQLCipher, con el esquema y las migraciones en SQL escrito a mano — un
  sistema con datos clínicos debe tener su esquema legible sin compilar nada.
- **Backend**: FastAPI (Python) + PostgreSQL.
- **Sync**: cola local con timestamp, resolución "último gana" + log de auditoría.
- **Exportación**: `.xlsx` vía openpyxl. Ficha de identidad y dataset clínico en
  archivos separados. El dataset clínico sale con Protocolo A/B, nunca desciegado.
- **Idioma**: código, comentarios y documentación en español. Los usuarios son médicos
  cubanos y el dominio es clínico en español.

---

## Estado de decisiones pendientes

Se actualizan aquí, no en el código.

**Bloqueantes para enrolar pacientes reales**

1. **Aprobación del CEI** de cada institución participante. El cronograma la sitúa en
   los meses 1–2; otra sección del proyecto afirma que ya existe. Contradicción a
   resolver con la investigadora principal.
2. **Cálculo de tamaño muestral.** El proyecto declara muestra consecutiva sin cálculo
   formal de potencia; en limitaciones menciona que se requieren más de 100 individuos.
   Sin esto el estudio puede quedar subpotenciado. Corresponde al bioestadista.
3. **Semilla y longitud de la secuencia** (restricción 7). Fijarlas al activar el
   estudio, no antes.
4. **Política de reparto de la secuencia.** El esquema central ya impide la
   colisión: tramos disjuntos por dispositivo, con restricción de solapamiento,
   y clave primaria por posición. Falta decidir **quién asigna los tramos, con
   qué holgura, y qué hace la app cuando se queda sin tramo y sin conexión.**
   La respuesta a lo último tiene que ser *dejar de enrolar*: improvisar una
   asignación es exactamente lo que la aleatorización pre-generada evita. Ver
   `docs/BACKEND.md`.

**Contradicciones internas de los documentos fuente**

4. **Tiempo mínimo de VMI para incluir**: el protocolo dice >24 h, el proyecto dice
   >48 h. Afecta directamente los criterios de elegibilidad programados.
5. **Nivel de cegamiento**: el resumen del proyecto dice "triple ciego", la metodología
   dice "cegamiento simple" y la tabla de sesgos dice "parcial". La implementación
   asume cegamiento de seleccionadores, evaluadores y analistas, que es lo que describe
   la metodología.

**Decisiones de alcance**

6. **Acumulación de funciones**: si un mismo médico puede cumplir varias.
   Implementado como configuración (`StudyConfig.permiteAcumularRoles`), hoy en
   `true`. El sistema ya identifica la combinación que rompe el cegamiento del
   desenlace principal: aplicador + evaluador de desenlaces en la misma persona.
7. **RSBI: categoría o número.** El Anexo 4 lo recoge por categorías
   (> 105 · ≤ 105 · ≤ 58) y así está implementado. Un 92 y un 104 caen en la
   misma y el dataset deja de distinguirlos. Recoger el número y calcular la
   categoría cuesta lo mismo; al revés no tiene vuelta. Ver
   `docs/RANGOS_PENDIENTES.md`.
8. **Unidades de dos duraciones** (detención de sedación, tiempo entre PVE y
   extubación). Hoy en horas con un decimal. Fijarlo antes del primer paciente:
   mezclar unidades en una columna es un error que no se ve mirando los datos.
9. **Corriente cualitativa**: encuestas Likert al personal, entrevistas
   semiestructuradas y checklist de adherencia con auditoría. Sujeto distinto (el
   investigador, no el paciente). ¿Entra al MVP?
10. **Sobres sellados**: el proyecto describe sobres físicos numerados con el
    protocolo dentro. ¿La app los reemplaza, o coexisten y la app registra el
    resultado? Cambia el flujo de enrolamiento, y es la misma decisión que el
    reparto de la secuencia entre dispositivos (bloqueante §4).
11. **Rangos clínicos** de cada campo numérico. Van vacíos hasta que un
    intensivista los fije: `docs/RANGOS_PENDIENTES.md` está listo para
    rellenar. Hay una prueba que falla si alguien los pone sin pasar por ahí.
12. **Nombre final del sistema.** "SIVAP" es provisional; el estudio se llama
    LIVERE.

---

## Progresión por hitos

Construcción por hitos con checkpoint de aprobación del equipo antes de avanzar.
Estado en `docs/PENDIENTE.md`; plan de corrección de rumbo en
`docs/REENCAMINAMIENTO.md`.

**Regla de secuencia**: las correcciones estructurales (cegamiento, modelo por
eventos, institución, roles) se completan **antes** de escribir el backend. Una vez
exista esquema en PostgreSQL con datos sincronizados, cada una pasa de refactor a
migración. Al 20 ago 2026 están todas hechas: el backend queda desbloqueado salvo
por el reparto de la secuencia entre dispositivos (pendiente bloqueante §4).

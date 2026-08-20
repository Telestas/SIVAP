# CLAUDE.md — Constitución del repositorio SIVAP

Este archivo define las reglas permanentes del proyecto. Cualquier sesión de Claude Code debe leerlo antes de generar o modificar código. Estas reglas no se negocian salvo decisión explícita del equipo, documentada aquí.

---

## Qué es este proyecto

Sistema (app Flutter móvil + web, backend FastAPI + PostgreSQL) para automatizar un estudio de cohorte que valida un protocolo clínico nuevo frente al vigente, en un hospital cubano, ejecutado por un equipo de médicos investigadores sin bioestadista ni desarrollador dedicado.

Ver `01_BASES_MVP_SIVAP.md` para el alcance completo.

---

## Glosario del dominio

- **Ficha del paciente**: identidad (nombre, contacto). Se crea una sola vez.
- **Registro de visita**: entrada de datos clínicos en un punto de tiempo fijo (Día 1, 3, 5, 10, 14). Es una entidad separada de la ficha, no una edición de la ficha.
- **Protocolo**: "viejo" (vigente) o "nuevo" (en validación).
- **Asignación**: proceso de determinar qué protocolo recibe un paciente. Módulo desacoplado (ver restricción más abajo).
- **Investigador**: usuario del sistema, con uno de tres roles (Observador, Recolector de campo, Administrador).

---

## Restricciones permanentes (NO NEGOCIABLES)

1. **Separación ficha/visita**: la identidad del paciente y los datos clínicos de cada visita viven en entidades separadas, vinculadas por un ID interno. Nunca fusionar en una sola tabla/modelo por conveniencia de desarrollo.

2. **Sin ediciones silenciosas**: ningún registro de visita ya enviado se sobrescribe directamente. Toda corrección genera una entrada de auditoría con: valor anterior, valor nuevo, autor, fecha/hora, motivo. Esto aplica incluso al rol Administrador.

3. **Formularios de visita configurables, no hardcodeados**: los campos de cada visita se definen como datos (nombre, tipo, obligatoriedad, validación), no como estructuras fijas en el código de la app. Un ajuste de protocolo se resuelve editando la definición, no recompilando la app.

4. **Módulo de asignación desacoplado**: la lógica que decide qué protocolo recibe un paciente vive en un componente aislado y reemplazable.

   **Método vigente** (decisión del equipo, 20 ago 2026): **aleatorización simple generada por computadora**. La secuencia completa —un código binario, `0` = protocolo vigente, `1` = protocolo nuevo— se genera a partir de una **semilla registrada**, antes de enrolar al primer paciente, y se consume en orden.

   Tres condiciones que no se relajan:

   - **La secuencia se genera entera antes del primer paciente.** Nunca se sortea en el momento de enrolar: sortear sobre la marcha permite repetir el sorteo hasta obtener la rama que se prefiere, y eso no deja rastro.
   - **La semilla queda por escrito** en el acta del estudio. Es lo que hace la aleatorización auditable: cualquiera puede regenerar la misma secuencia y verificar que las asignaciones registradas son las que tocaban. Un azar irreproducible no se puede auditar.
   - **La semilla no se cambia a mitad del estudio.** Hacerlo invalida la trazabilidad de todo lo asignado hasta ese momento.

   Nunca implementar selección manual del protocolo por el investigador sin una regla objetiva documentada — esto introduce sesgo de selección. Y no "corregir" el reparto para que quede 50/50 exacto: en aleatorización simple el desequilibrio moderado es esperado y legítimo. Si el desequilibrio llegara a importar, la salida es aleatorización por bloques, que es otra implementación del mismo módulo — no un parche sobre esta.

5. **Cifrado obligatorio**: base de datos local (dispositivo) cifrada en reposo. Comunicación cliente-servidor siempre por TLS. Nunca almacenar contraseñas ni tokens en texto plano.

6. **Roles y permisos** (ver tabla en `01_BASES_MVP_SIVAP.md`, sección 4): Observador (solo lectura), Recolector de campo (crea pacientes y visitas propias, no edita visitas enviadas), Administrador (control total con auditoría). Cualquier endpoint nuevo debe declarar explícitamente qué rol lo puede invocar.

7. **Offline-first real**: toda funcionalidad de captura de datos debe operar sin conexión. La sincronización es un proceso posterior, nunca un requisito para poder trabajar.

8. **Consentimiento informado**: el sistema no admite enrolamiento de pacientes reales hasta que exista un flag explícito de "consentimiento y protocolo aprobados por el CEI" — este flag se gestiona a nivel de configuración del estudio, no del código.

---

## Convenciones técnicas

- **Frontend/móvil**: Flutter (Dart).
- **Persistencia local**: SQLite cifrado con SQLCipher (`package:sqlite3` + `sqlcipher_flutter_libs`), con el esquema y las migraciones en SQL escrito a mano.

  Se decidió así en vez de Drift o Isar (20 ago 2026): un sistema que guarda datos clínicos debe tener su esquema legible sin compilar nada, y un generador de código es un paso más en un equipo sin desarrollador dedicado. Si más adelante se prefiere Drift, se monta encima — las pantallas hablan con `StudyRepository`, no con la base.

  **La clave de cifrado nunca va en el código.** Se genera en el dispositivo, con `Random.secure`, y se guarda en el Keystore/Keychain del sistema. Una clave dentro del .apk no cifra nada.

  **Al abrir se verifica `PRAGMA cipher_version` y se aborta si falta.** Sin esa comprobación, un fallo de empaquetado dejaría la base en claro sin que nadie se enterara.

  **En navegador no hay cifrado local posible** y no se finge que lo hay: no existe archivo que cifrar, y una clave guardada en el navegador no protege de nadie. La web es el panel de administración y debe leer del servidor, no capturar datos.
- **Backend**: FastAPI (Python). PostgreSQL como base central.
- **Sync**: cola local con timestamp; resolución de conflictos "último gana" + registro de auditoría.
- **Exportación**: generación de .xlsx vía openpyxl, con la ficha y los datos clínicos exportables por separado (para permitir compartir solo la parte clínica sin identidad).

---

## Estado de decisiones pendientes (actualizar aquí, no en el código)

- **Método de aleatorización**: ~~pendiente~~ **decidido (20 ago 2026)**: aleatorización simple generada por computadora desde semilla registrada (ver restricción 4). Queda pendiente que el equipo fije la semilla y la longitud de la secuencia del estudio real, y lo deje en el acta.
- **Campos exactos por visita**: pendiente de listado del equipo médico.
- **Nombre final del proyecto**: provisional "SIVAP".
- **Aprobación del CEI**: pendiente (consentimiento en borrador).

---

## Progresión por hitos

Este proyecto se construye por hitos (Hito 0, 1, 2...), cada uno con checkpoint de aprobación del equipo antes de avanzar al siguiente. Ver `02_PROMPT_CLAUDE_CODE.md` (a generar) para la secuencia detallada.


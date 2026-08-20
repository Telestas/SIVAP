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

4. **Módulo de asignación desacoplado**: la lógica que decide qué protocolo recibe un paciente vive en un componente aislado y reemplazable. Por defecto: aleatorización simple pre-generada (lista consumida en orden). Nunca implementar selección manual del protocolo por el investigador sin una regla objetiva documentada — esto introduce sesgo de selección.

5. **Cifrado obligatorio**: base de datos local (dispositivo) cifrada en reposo. Comunicación cliente-servidor siempre por TLS. Nunca almacenar contraseñas ni tokens en texto plano.

6. **Roles y permisos** (ver tabla en `01_BASES_MVP_SIVAP.md`, sección 4): Observador (solo lectura), Recolector de campo (crea pacientes y visitas propias, no edita visitas enviadas), Administrador (control total con auditoría). Cualquier endpoint nuevo debe declarar explícitamente qué rol lo puede invocar.

7. **Offline-first real**: toda funcionalidad de captura de datos debe operar sin conexión. La sincronización es un proceso posterior, nunca un requisito para poder trabajar.

8. **Consentimiento informado**: el sistema no admite enrolamiento de pacientes reales hasta que exista un flag explícito de "consentimiento y protocolo aprobados por el CEI" — este flag se gestiona a nivel de configuración del estudio, no del código.

---

## Convenciones técnicas

- **Frontend/móvil**: Flutter (Dart). Persistencia local con Drift o Isar.
- **Backend**: FastAPI (Python). PostgreSQL como base central.
- **Sync**: cola local con timestamp; resolución de conflictos "último gana" + registro de auditoría.
- **Exportación**: generación de .xlsx vía openpyxl, con la ficha y los datos clínicos exportables por separado (para permitir compartir solo la parte clínica sin identidad).

---

## Estado de decisiones pendientes (actualizar aquí, no en el código)

- **Método de aleatorización final**: pendiente de confirmación del bioestadista. Por defecto: aleatorización simple.
- **Campos exactos por visita**: pendiente de listado del equipo médico.
- **Nombre final del proyecto**: provisional "SIVAP".
- **Aprobación del CEI**: pendiente (consentimiento en borrador).

---

## Progresión por hitos

Este proyecto se construye por hitos (Hito 0, 1, 2...), cada uno con checkpoint de aprobación del equipo antes de avanzar al siguiente. Ver `02_PROMPT_CLAUDE_CODE.md` (a generar) para la secuencia detallada.


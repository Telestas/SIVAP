-- SIVAP · Migración 003 — el Anexo 4 revisado
--
-- El equipo reescribió el formulario y lo dejó en cinco módulos. La captura
-- pierde tipos de evento y gana condicionales, cálculos y una puerta de
-- criterios de exclusión; de todo eso, lo único que llega hasta aquí es la
-- lista de tipos, porque los campos van como documento en
-- `definicion_formulario` (CLAUDE.md §5).
--
-- Qué desaparece, y a dónde va:
--
--   estratificacion_riesgo → se calcula dentro del enrolamiento
--   evaluacion_diaria      → el equipo la retiró
--   traqueostomia          → un campo del módulo 4
--   soporte_post_extubacion→ campos del módulo 4
--   reintubacion           → un campo del módulo 5
--   egreso_uci             → campos del módulo 5, ahora `desenlaces`
--
-- Un tipo de un ENUM de PostgreSQL no se puede quitar: hay que rehacer el
-- tipo. La conversión de vuelta falla si alguna fila usa un valor retirado, y
-- eso es lo que se quiere — mejor que la migración se detenga a que convierta
-- en silencio un evento a otra cosa. Hoy no hay pacientes reales (§13), así
-- que no hay nada que convertir.

BEGIN;

-- ══════════════════════════════════════════════════════════════════
-- Tipos de evento
-- ══════════════════════════════════════════════════════════════════

-- `dataset_clinico` lee `evento.tipo`, y PostgreSQL no deja cambiar el tipo de
-- una columna de la que cuelga una vista. Se rehace igual que estaba: es la
-- misma consulta, y sigue saliendo con la rama en A/B y sin identidad.
DROP VIEW dataset_clinico;

ALTER TABLE evento ALTER COLUMN tipo TYPE TEXT;
DROP TYPE tipo_evento;

CREATE TYPE tipo_evento AS ENUM (
  'enrolamiento',
  'cribado',
  'prueba_ventilacion_espontanea',
  'extubacion',
  'desenlaces',
  'seguimiento_post_egreso'
);

ALTER TABLE evento
  ALTER COLUMN tipo TYPE tipo_evento USING tipo::tipo_evento;

CREATE VIEW dataset_clinico WITH (security_invoker = true) AS
  SELECT p.codigo               AS paciente,
         p.institucion_codigo   AS centro,
         a.protocolo            AS rama,
         p.edad,
         p.sexo,
         e.tipo                 AS evento,
         e.ocurrencia,
         e.fecha_ocurrencia,
         v.campo,
         v.tipo                 AS tipo_valor,
         v.valor
  FROM paciente p
  JOIN asignacion a ON a.paciente_id = p.id
  JOIN evento e     ON e.paciente_id = p.id
  JOIN evento_valor_vigente v ON v.evento_id = e.id;

GRANT SELECT ON dataset_clinico TO sivap_api, sivap_analista;

-- ══════════════════════════════════════════════════════════════════
-- Funciones
-- ══════════════════════════════════════════════════════════════════
--
-- Fuera `observador`: el protocolo revisado enumera quién necesita acceso y no
-- lo incluye. Una función que nadie tiene asignada es superficie de permisos
-- que nadie ha revisado, y aquí los permisos sostienen el cegamiento.
--
-- Las dos funciones que el documento nombra —«reclutador» y
-- «reclutador-aplicador»— no necesitan valores nuevos: la segunda es la suma
-- de dos de los que ya hay. Es la combinación habitual en un equipo pequeño y
-- no compromete el cegamiento; la que sí lo rompe, aplicador + evaluador de
-- desenlaces, la sigue señalando la vista de abajo.

DROP VIEW IF EXISTS investigador_con_cegamiento_comprometido;

ALTER TABLE investigador_rol ALTER COLUMN rol TYPE TEXT;
DROP TYPE rol;

CREATE TYPE rol AS ENUM (
  'reclutador',
  'aplicador',
  'evaluador_desenlaces',
  'analista',
  'investigador_principal'
);

ALTER TABLE investigador_rol ALTER COLUMN rol TYPE rol USING rol::rol;

-- La combinación que rompe el cegamiento del desenlace principal: quien aplicó
-- el protocolo sabe qué rama es, y luego juzgaría si la extubación falló.
--
-- No se prohíbe en la base porque la investigadora principal puede necesitar
-- admitirla en un centro con poco personal. Se deja **visible**, para que la
-- decisión sea consciente y quede en el acta.
CREATE VIEW investigador_con_cegamiento_comprometido
  WITH (security_invoker = true) AS
  SELECT i.id, i.usuario, i.nombre, i.institucion_codigo
  FROM investigador i
  WHERE EXISTS (SELECT 1 FROM investigador_rol r
                WHERE r.investigador_id = i.id AND r.rol = 'aplicador')
    AND EXISTS (SELECT 1 FROM investigador_rol r
                WHERE r.investigador_id = i.id AND r.rol = 'evaluador_desenlaces');

GRANT SELECT ON investigador_con_cegamiento_comprometido TO sivap_api;

INSERT INTO migracion (version) VALUES ('003');

COMMIT;

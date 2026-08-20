-- SIVAP · Esquema central del ensayo LIVERE
-- Migración 001 — esquema inicial
--
-- PostgreSQL 16. Se ejecuta con el rol propietario (`sivap_admin`); la api
-- corre con `sivap_api`, que tiene menos privilegios a propósito.
--
-- El esquema hace valer en la propia base tres cosas que no pueden depender de
-- que la aplicación esté bien escrita:
--
--   1. La auditoría no se puede modificar ni borrar.
--   2. Dos pacientes no pueden ocupar la misma posición de la secuencia de
--      aleatorización.
--   3. Quien analiza no puede leer la identidad de los pacientes.
--
-- Una aplicación se reescribe mal cualquier día. Estas tres, no.
--
-- PENDIENTE al implementar: los identificadores son UUID aquí y la app genera
-- cadenas con prefijo («p-3f9a…»). Antes de la primera sincronización hay que
-- pasar `Ids.nuevo` a UUIDv4. Es preferible cambiar el cliente que aflojar el
-- tipo de la columna: el tipo `uuid` valida, indexa mejor y ocupa la mitad.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS btree_gist; -- restricción de solapamiento

-- ══════════════════════════════════════════════════════════════════
-- Tipos
-- ══════════════════════════════════════════════════════════════════

-- Las dos ramas del ensayo, y nada más.
--
-- **Cuál es LIVERE y cuál el manejo convencional no está en esta base**
-- (CLAUDE.md §2). La correspondencia vive en el expediente del estudio, en
-- papel, y se revela una sola vez al cierre. No añadir aquí un valor, columna
-- ni comentario que lo describa.
CREATE TYPE protocolo AS ENUM ('a', 'b');

CREATE TYPE rol AS ENUM (
  'reclutador',
  'aplicador',
  'evaluador_desenlaces',
  'analista',
  'investigador_principal',
  'observador'
);

CREATE TYPE tipo_evento AS ENUM (
  'enrolamiento',
  'estratificacion_riesgo',
  'cribado',
  'evaluacion_diaria',
  'prueba_ventilacion_espontanea',
  'traqueostomia',
  'extubacion',
  'soporte_post_extubacion',
  'reintubacion',
  'egreso_uci',
  'seguimiento_post_egreso'
);

CREATE TYPE sexo AS ENUM ('masculino', 'femenino');

CREATE TYPE tipo_valor AS ENUM ('numero', 'texto', 'booleano', 'fecha', 'lista');

CREATE TYPE entidad_auditada AS ENUM
  ('ficha', 'evento', 'consentimiento', 'usuario');

-- ══════════════════════════════════════════════════════════════════
-- Configuración del estudio
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE institucion (
  codigo        TEXT PRIMARY KEY CHECK (codigo ~ '^[A-Z]{2,4}$'),
  nombre        TEXT NOT NULL,
  coordinador   BOOLEAN NOT NULL DEFAULT FALSE,

  -- Restricción CLAUDE.md §13: sin aprobación del CEI **de esa institución**
  -- no se enrolan pacientes reales allí. La aprobación es por centro, no del
  -- estudio en bloque: un centro puede empezar antes que otro.
  cei_aprobado     BOOLEAN NOT NULL DEFAULT FALSE,
  cei_codigo       TEXT,
  cei_aprobado_en  DATE,

  creado_en     TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT cei_coherente CHECK (
    NOT cei_aprobado OR (cei_codigo IS NOT NULL AND cei_aprobado_en IS NOT NULL)
  )
);

COMMENT ON TABLE institucion IS
  'Centros participantes. Un solo coordinador; el resto, participantes.';

CREATE UNIQUE INDEX un_solo_coordinador
  ON institucion ((TRUE)) WHERE coordinador;

-- Definición de formularios, versionada y servida a la app.
--
-- Restricción CLAUDE.md §5: los campos son datos, no código. Se guarda como
-- documento JSON y no repartida en tablas porque **la unidad que importa es la
-- versión completa**: un dataset exportado corresponde a exactamente una
-- versión de la definición, y trocearla haría posible tener media definición
-- vieja y media nueva conviviendo.
CREATE TABLE definicion_formulario (
  version      TEXT PRIMARY KEY,
  definicion   JSONB NOT NULL,
  publicada_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  activa       BOOLEAN NOT NULL DEFAULT FALSE,
  notas        TEXT
);

CREATE UNIQUE INDEX una_definicion_activa
  ON definicion_formulario ((TRUE)) WHERE activa;

-- ══════════════════════════════════════════════════════════════════
-- Personas y dispositivos
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE investigador (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario            TEXT NOT NULL UNIQUE,
  nombre             TEXT NOT NULL,
  -- Argon2id o bcrypt. Nunca la contraseña (CLAUDE.md §10).
  credencial_hash    TEXT NOT NULL,
  institucion_codigo TEXT NOT NULL REFERENCES institucion(codigo),
  activo             BOOLEAN NOT NULL DEFAULT TRUE,
  creado_en          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Un investigador lleva un conjunto de funciones, no una sola: en equipos
-- pequeños acumular es lo normal (BASES §4).
CREATE TABLE investigador_rol (
  investigador_id UUID NOT NULL REFERENCES investigador(id) ON DELETE CASCADE,
  rol             rol  NOT NULL,
  PRIMARY KEY (investigador_id, rol)
);

-- La combinación que rompe el cegamiento del desenlace principal: quien aplicó
-- el protocolo sabe qué rama es, y luego juzgaría si la extubación falló.
--
-- No se prohíbe en la base porque la investigadora principal puede necesitar
-- admitirla en un centro con poco personal. Se deja **visible**, para que la
-- decisión sea consciente y quede en el acta.
CREATE VIEW investigador_con_cegamiento_comprometido
  WITH (security_invoker = true) AS
  SELECT i.id, i.usuario, i.institucion_codigo
  FROM investigador i
  WHERE EXISTS (SELECT 1 FROM investigador_rol r
                WHERE r.investigador_id = i.id AND r.rol = 'aplicador')
    AND EXISTS (SELECT 1 FROM investigador_rol r
                WHERE r.investigador_id = i.id AND r.rol = 'evaluador_desenlaces');

CREATE TABLE dispositivo (
  id                    UUID PRIMARY KEY,
  investigador_id       UUID NOT NULL REFERENCES investigador(id),
  etiqueta              TEXT NOT NULL,
  registrado_en         TIMESTAMPTZ NOT NULL DEFAULT now(),
  ultima_sincronizacion TIMESTAMPTZ
);

COMMENT ON TABLE dispositivo IS
  'Cada teléfono o tableta que captura datos. Hace falta para repartir la '
  'secuencia de aleatorización y para saber de dónde vino cada registro.';

-- ══════════════════════════════════════════════════════════════════
-- Aleatorización
-- ══════════════════════════════════════════════════════════════════

-- La secuencia del estudio.
--
-- **No hay columna para la semilla, y es deliberado** (CLAUDE.md §7). Al
-- sistema se carga la secuencia ya generada. Quien tuviera la semilla podría
-- calcular la secuencia entera y saber qué rama le toca al próximo paciente,
-- que es el sesgo de selección que la aleatorización existe para evitar. La
-- semilla vive en el expediente en papel, en custodia de la investigadora
-- principal, y sirve después para que un revisor externo regenere la secuencia
-- y compruebe que las asignaciones fueron las que tocaban.
CREATE TABLE secuencia (
  etiqueta       TEXT PRIMARY KEY,
  origen         TEXT NOT NULL
                 CHECK (origen IN ('generada_por_computadora', 'cargada')),
  codigo_binario TEXT NOT NULL CHECK (codigo_binario ~ '^[01]+$'),
  longitud       INTEGER NOT NULL GENERATED ALWAYS AS (length(codigo_binario)) STORED,
  generada_en    TIMESTAMPTZ NOT NULL,
  cargada_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
  activa         BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE UNIQUE INDEX una_secuencia_activa
  ON secuencia ((TRUE)) WHERE activa;

-- Reparto de la secuencia entre dispositivos.
--
-- **Esto es lo que resuelve el problema de trabajar sin conexión.** Si todos
-- los dispositivos consumieran de la misma lista, dos que estén sin cobertura
-- asignarían ambos la posición siguiente y, al sincronizar, dos pacientes
-- reclamarían la misma. Y ocurriría en silencio.
--
-- Es el equivalente digital de los sobres sellados y numerados: cada
-- dispositivo recibe un tramo propio y no puede tocar el de otro. La
-- restricción EXCLUDE hace imposible que dos tramos se solapen — no por
-- disciplina, sino porque la base lo rechaza.
CREATE TABLE secuencia_rango (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  secuencia_etiqueta TEXT NOT NULL REFERENCES secuencia(etiqueta),
  dispositivo_id     UUID NOT NULL REFERENCES dispositivo(id),
  institucion_codigo TEXT NOT NULL REFERENCES institucion(codigo),
  tramo              INT4RANGE NOT NULL,
  asignado_en        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT tramo_valido CHECK (NOT isempty(tramo) AND lower(tramo) >= 1),
  CONSTRAINT tramos_sin_solape
    EXCLUDE USING gist (secuencia_etiqueta WITH =, tramo WITH &&)
);

-- ══════════════════════════════════════════════════════════════════
-- Pacientes
-- ══════════════════════════════════════════════════════════════════

-- Datos del paciente que forman parte del análisis. Sin identidad.
--
-- El código sale de la posición de aleatorización: «HC-041» es el paciente que
-- ocupó la posición 41. Como las posiciones vienen de tramos disjuntos, los
-- códigos no chocan entre dispositivos aunque se generen sin conexión — y
-- además atan el código del paciente a su asignación, que es la práctica
-- habitual en ensayos.
CREATE TABLE paciente (
  id                 UUID PRIMARY KEY,
  codigo             TEXT NOT NULL,
  institucion_codigo TEXT NOT NULL REFERENCES institucion(codigo),
  -- Comprobación de plausibilidad, no de elegibilidad. Los criterios de
  -- inclusión los aplica el reclutador y están en disputa en las fuentes
  -- (>24 h o >48 h de VMI): grabarlos aquí bloquearía la captura de un dato
  -- verdadero, que es justo lo que CLAUDE.md §14 prohíbe.
  edad               INTEGER NOT NULL CHECK (edad BETWEEN 0 AND 130),
  sexo               sexo NOT NULL,
  enrolado_por       UUID NOT NULL REFERENCES investigador(id),
  dispositivo_id     UUID NOT NULL REFERENCES dispositivo(id),
  enrolado_en        TIMESTAMPTZ NOT NULL,
  recibido_en        TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (institucion_codigo, codigo)
);

-- Cada asignación consumida.
--
-- La clave primaria es (secuencia, posición): **dos pacientes no pueden ocupar
-- la misma posición**. Si dos dispositivos mal configurados lo intentaran, el
-- segundo choca contra la base en vez de corromper el reparto en silencio.
CREATE TABLE asignacion (
  secuencia_etiqueta TEXT      NOT NULL REFERENCES secuencia(etiqueta),
  posicion           INTEGER   NOT NULL CHECK (posicion >= 1),
  protocolo          protocolo NOT NULL,
  -- Sin ON DELETE CASCADE, y es deliberado: **un paciente aleatorizado no se
  -- borra**. La posición se consumió y eso es permanente; hacer desaparecer a
  -- un paciente ya asignado es la puerta trasera del sesgo de selección. Una
  -- retirada del estudio se registra como tal, no borrando la fila.
  paciente_id        UUID      NOT NULL UNIQUE REFERENCES paciente(id),
  dispositivo_id     UUID      NOT NULL REFERENCES dispositivo(id),
  asignado_en        TIMESTAMPTZ NOT NULL,
  recibido_en        TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (secuencia_etiqueta, posicion)
);

-- Comprueba que la posición asignada coincide con lo que dice la secuencia.
-- Es la verificación que un auditor externo haría a mano; hacerla aquí
-- significa que una asignación incoherente no llega ni a guardarse.
CREATE OR REPLACE FUNCTION asignacion_coincide_con_secuencia()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  bit CHAR;
BEGIN
  SELECT substr(codigo_binario, NEW.posicion, 1) INTO bit
  FROM secuencia WHERE etiqueta = NEW.secuencia_etiqueta;

  IF bit IS NULL OR bit = '' THEN
    RAISE EXCEPTION 'La posición % está fuera de la secuencia %',
      NEW.posicion, NEW.secuencia_etiqueta;
  END IF;

  IF (bit = '1') <> (NEW.protocolo = 'b') THEN
    RAISE EXCEPTION
      'La asignación no coincide con la secuencia en la posición %', NEW.posicion;
  END IF;

  RETURN NEW;
END $$;

CREATE TRIGGER asignacion_verificada
  BEFORE INSERT ON asignacion
  FOR EACH ROW EXECUTE FUNCTION asignacion_coincide_con_secuencia();

-- Identidad, en su propia tabla.
--
-- Restricción CLAUDE.md §1. No es una separación cosmética: el rol
-- `sivap_analista` **no tiene permiso de lectura sobre esta tabla**, así que el
-- dataset que sale para análisis no puede contener identidad ni por error.
--
-- Restricción §9: ni carné de identidad ni dirección. El Anexo 4 no los pide.
-- Nombre e historia clínica se conservan por decisión explícita del equipo
-- —hace falta identificar al paciente en la sala— y son la excepción a
-- justificar ante el CEI.
CREATE TABLE identidad (
  paciente_id             UUID PRIMARY KEY REFERENCES paciente(id) ON DELETE CASCADE,
  nombre                  TEXT NOT NULL,
  numero_historia_clinica TEXT NOT NULL,
  telefono_principal      TEXT NOT NULL,
  telefono_secundario     TEXT
);

CREATE TABLE consentimiento (
  id                UUID PRIMARY KEY,
  paciente_id       UUID NOT NULL UNIQUE REFERENCES paciente(id) ON DELETE CASCADE,
  version_documento TEXT NOT NULL,
  codigo_cei        TEXT NOT NULL,
  firmado_en        TIMESTAMPTZ NOT NULL,
  testigo_id        UUID NOT NULL REFERENCES investigador(id),
  -- Trazos normalizados 0..1, independientes del tamaño de la pantalla que
  -- capturó. Se guardan como documento porque no se consultan por partes.
  firma             JSONB NOT NULL,
  recibido_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ══════════════════════════════════════════════════════════════════
-- Eventos clínicos
-- ══════════════════════════════════════════════════════════════════

-- Restricción CLAUDE.md §4: la captura se estructura por hitos del proceso, no
-- por calendario. No hay fecha programada ni estado «perdido»: un evento que no
-- ocurrió simplemente no tiene fila.
--
-- Solo llegan aquí los eventos **registrados**. Los borradores se quedan en el
-- dispositivo: sincronizar datos a medio teclear llenaría la base central de
-- registros incompletos que nadie sabría si son definitivos.
CREATE TABLE evento (
  id                 UUID PRIMARY KEY,
  paciente_id        UUID NOT NULL REFERENCES paciente(id),
  tipo               tipo_evento NOT NULL,
  ocurrencia         INTEGER NOT NULL CHECK (ocurrencia >= 1),
  fecha_ocurrencia   DATE NOT NULL,
  institucion_codigo TEXT NOT NULL REFERENCES institucion(codigo),
  recolector_id      UUID NOT NULL REFERENCES investigador(id),
  dispositivo_id     UUID NOT NULL REFERENCES dispositivo(id),
  fecha_captura      TIMESTAMPTZ NOT NULL,
  recibido_en        TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (paciente_id, tipo, ocurrencia)
);

CREATE INDEX evento_por_paciente ON evento (paciente_id, fecha_ocurrencia);
CREATE INDEX evento_por_institucion ON evento (institucion_codigo, tipo);

-- Valores capturados, **versionados y solo-añadir**.
--
-- Aquí está la diferencia importante con la base del dispositivo. Una
-- corrección no sobrescribe: inserta una versión nueva. Así la resolución
-- «último gana» de la sincronización no pierde nada —la versión anterior sigue
-- ahí— y el historial completo de cada dato existe sin tener que reconstruirlo
-- desde la auditoría.
--
-- En un sistema que guarda datos de un ensayo clínico, poder demostrar qué
-- decía un campo en una fecha concreta no es una comodidad: es lo que se
-- pregunta en una inspección.
CREATE TABLE evento_valor (
  evento_id     UUID NOT NULL REFERENCES evento(id) ON DELETE CASCADE,
  campo         TEXT NOT NULL,
  version       INTEGER NOT NULL CHECK (version >= 1),
  tipo          tipo_valor NOT NULL,
  valor         TEXT,
  capturado_en  TIMESTAMPTZ NOT NULL,
  autor_id      UUID NOT NULL REFERENCES investigador(id),
  recibido_en   TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (evento_id, campo, version)
);

-- El valor vigente de cada campo: el de mayor versión.
--
-- `security_invoker` a propósito: la vista se ejecuta con los permisos de quien
-- consulta, no con los del dueño. Sin esto, una vista futura que tocara
-- `identidad` se la serviría al analista pese a habérsela revocado.
CREATE VIEW evento_valor_vigente WITH (security_invoker = true) AS
  SELECT DISTINCT ON (evento_id, campo)
         evento_id, campo, tipo, valor, capturado_en, autor_id, version
  FROM evento_valor
  ORDER BY evento_id, campo, version DESC;

-- ══════════════════════════════════════════════════════════════════
-- Auditoría
-- ══════════════════════════════════════════════════════════════════

-- Restricción CLAUDE.md §3. Solo-añadir, y lo impone la base.
--
-- La regla ya se comprueba en la aplicación, pero una aplicación se reescribe
-- mal cualquier día. Con estos disparadores, ni un UPDATE lanzado a mano contra
-- la base puede alterar el historial. Un registro de auditoría que se puede
-- editar no es un registro de auditoría.
CREATE TABLE auditoria (
  id                   UUID PRIMARY KEY,
  ocurrido_en          TIMESTAMPTZ NOT NULL,
  autor_id             UUID NOT NULL REFERENCES investigador(id),
  entidad              entidad_auditada NOT NULL,
  entidad_id           UUID NOT NULL,
  descripcion_objetivo TEXT NOT NULL,
  campo                TEXT NOT NULL,
  valor_anterior       TEXT,
  valor_nuevo          TEXT,
  motivo               TEXT NOT NULL CHECK (length(btrim(motivo)) > 0),
  dispositivo_id       UUID REFERENCES dispositivo(id),
  recibido_en          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX auditoria_por_entidad ON auditoria (entidad_id, ocurrido_en DESC);

CREATE OR REPLACE FUNCTION rechazar_modificacion()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'La tabla % es de solo inserción', TG_TABLE_NAME;
END $$;

CREATE TRIGGER auditoria_sin_update BEFORE UPDATE ON auditoria
  FOR EACH ROW EXECUTE FUNCTION rechazar_modificacion();
CREATE TRIGGER auditoria_sin_delete BEFORE DELETE ON auditoria
  FOR EACH ROW EXECUTE FUNCTION rechazar_modificacion();

-- Los valores son solo-añadir por la misma razón.
CREATE TRIGGER evento_valor_sin_update BEFORE UPDATE ON evento_valor
  FOR EACH ROW EXECUTE FUNCTION rechazar_modificacion();
CREATE TRIGGER evento_valor_sin_delete BEFORE DELETE ON evento_valor
  FOR EACH ROW EXECUTE FUNCTION rechazar_modificacion();

-- ══════════════════════════════════════════════════════════════════
-- Sincronización
-- ══════════════════════════════════════════════════════════════════

-- Diario de lotes recibidos.
--
-- Sirve para dos cosas prácticas: reintentar un lote sin duplicar nada, y
-- responder «esto llegó o no llegó» cuando un investigador dice que capturó
-- algo que no aparece. Con conectividad intermitente, esa pregunta se hace
-- sola.
CREATE TABLE lote_sincronizacion (
  id              UUID PRIMARY KEY,
  dispositivo_id  UUID NOT NULL REFERENCES dispositivo(id),
  recibido_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
  registros       INTEGER NOT NULL,
  aceptados       INTEGER NOT NULL,
  rechazados      INTEGER NOT NULL,
  detalle         JSONB
);

CREATE INDEX lote_por_dispositivo
  ON lote_sincronizacion (dispositivo_id, recibido_en DESC);

-- ══════════════════════════════════════════════════════════════════
-- Vista de exportación
-- ══════════════════════════════════════════════════════════════════

-- El dataset que recibe el bioestadista: formato largo, una fila por valor.
--
-- Sin identidad —no hay JOIN con `identidad`, y el rol que lo consulta ni
-- siquiera podría hacerlo— y con la rama en A/B. **Nunca sale desciegado**: la
-- correspondencia se aplica fuera del sistema, una vez, al cierre del estudio
-- (CLAUDE.md §2, BASES §10).
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

-- ══════════════════════════════════════════════════════════════════
-- Roles de base de datos
-- ══════════════════════════════════════════════════════════════════
--
-- Los privilegios son la última línea de defensa: valen aunque la api tenga un
-- fallo. Que el analista no pueda leer la identidad no depende de que alguien
-- se acuerde de filtrarla en una consulta.

CREATE ROLE sivap_api NOLOGIN;
CREATE ROLE sivap_analista NOLOGIN;

GRANT USAGE ON SCHEMA public TO sivap_api, sivap_analista;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO sivap_api;
-- Ni la api puede tocar lo que es solo-añadir. Los disparadores lo impedirían
-- igual; quitar el privilegio hace que ni se intente.
REVOKE UPDATE, DELETE ON auditoria, evento_valor FROM sivap_api;

GRANT SELECT ON paciente, evento, evento_valor, evento_valor_vigente,
                asignacion, auditoria, institucion, dataset_clinico
  TO sivap_analista;
-- La línea que importa de todo este bloque.
REVOKE ALL ON identidad FROM sivap_analista;

COMMIT;

-- Migración 002 — sesiones de sincronización
--
-- La captura **no** depende de esto (CLAUDE.md §12): un investigador entra en
-- la app validando su credencial contra el dispositivo y trabaja sin conexión
-- todo lo que haga falta. El token solo sirve para hablar con el servidor.

BEGIN;

CREATE TABLE sesion (
  -- Se guarda el SHA-256 del token, no el token. Quien lea esta tabla no puede
  -- suplantar a nadie: es el mismo motivo por el que no se guardan contraseñas.
  token_hash      TEXT PRIMARY KEY,
  investigador_id UUID NOT NULL REFERENCES investigador(id) ON DELETE CASCADE,
  dispositivo_id  UUID REFERENCES dispositivo(id) ON DELETE CASCADE,
  creada_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Larga a propósito: un teléfono puede pasar semanas sin cobertura, y
  -- caducarle la sesión significaría que no puede enviar lo que ya capturó.
  expira_en       TIMESTAMPTZ NOT NULL,
  revocada_en     TIMESTAMPTZ
);

CREATE INDEX sesion_por_investigador ON sesion (investigador_id);

COMMENT ON TABLE sesion IS
  'Sesiones de sincronización. Revocables: un teléfono perdido se corta desde '
  'aquí sin tocar la credencial del investigador.';

-- Los privilegios de la migración 001 se dieron sobre las tablas que existían
-- entonces. Una tabla nueva no los hereda, así que hay que darlos —y dejar
-- dicho para las próximas que esto se olvida con facilidad.
GRANT SELECT, INSERT, UPDATE, DELETE ON sesion TO sivap_api;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO sivap_api;

INSERT INTO migracion (version) VALUES ('002');

COMMIT;

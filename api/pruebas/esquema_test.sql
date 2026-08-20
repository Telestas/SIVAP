-- Pruebas del esquema central.
--
-- No comprueban que las tablas existan —eso lo dice la migración— sino que las
-- garantías que el esquema promete se cumplen de verdad. Cada una intenta hacer
-- algo que debe ser imposible y falla si resulta que se pudo.
--
--   docker exec -i <contenedor> psql -U postgres -v ON_ERROR_STOP=1 \
--     < api/pruebas/esquema_test.sql

\set ON_ERROR_STOP on

BEGIN;

-- ── Semilla de datos ──────────────────────────────────────────────

INSERT INTO institucion (codigo, nombre, coordinador)
  VALUES ('HC', 'Centro de prueba', TRUE);

INSERT INTO investigador (id, usuario, nombre, credencial_hash, institucion_codigo)
  VALUES ('00000000-0000-4000-8000-000000000001', 'prueba', 'Dra. Prueba',
          'hash', 'HC');

INSERT INTO dispositivo (id, investigador_id, etiqueta)
  VALUES ('00000000-0000-4000-8000-0000000000d1',
          '00000000-0000-4000-8000-000000000001', 'tableta 1'),
         ('00000000-0000-4000-8000-0000000000d2',
          '00000000-0000-4000-8000-000000000001', 'tableta 2');

-- Secuencia: A B A B ...  (0 = A, 1 = B)
INSERT INTO secuencia (etiqueta, origen, codigo_binario, generada_en, activa)
  VALUES ('prueba', 'generada_por_computadora', '0101010101', now(), TRUE);

INSERT INTO paciente (id, codigo, institucion_codigo, edad, sexo,
                      enrolado_por, dispositivo_id, enrolado_en)
  VALUES ('00000000-0000-4000-8000-000000000101', 'HC-001', 'HC',
          62, 'masculino', '00000000-0000-4000-8000-000000000001',
          '00000000-0000-4000-8000-0000000000d1', now());

-- ══════════════════════════════════════════════════════════════════
-- 1 · La auditoría no se puede modificar ni borrar
-- ══════════════════════════════════════════════════════════════════

INSERT INTO auditoria (id, ocurrido_en, autor_id, entidad, entidad_id,
                       descripcion_objetivo, campo, valor_anterior, valor_nuevo,
                       motivo)
  VALUES ('00000000-0000-4000-8000-0000000000a1', now(),
          '00000000-0000-4000-8000-000000000001', 'evento',
          '00000000-0000-4000-8000-0000000000e1', 'HC-001 · PVE · 1',
          'fr_inicio', '92', '29', 'cifras transpuestas');

DO $$
BEGIN
  BEGIN
    UPDATE auditoria SET motivo = 'otra cosa';
    RAISE EXCEPTION 'FALLO: se pudo modificar el registro de auditoría';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FALLO%' THEN RAISE; END IF;
  END;

  BEGIN
    DELETE FROM auditoria;
    RAISE EXCEPTION 'FALLO: se pudo borrar el registro de auditoría';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FALLO%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'OK · la auditoría es de solo inserción';
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO auditoria (id, ocurrido_en, autor_id, entidad, entidad_id,
                           descripcion_objetivo, campo, motivo)
      VALUES ('00000000-0000-4000-8000-0000000000a2', now(),
              '00000000-0000-4000-8000-000000000001', 'evento',
              '00000000-0000-4000-8000-0000000000e1', 'x', 'y', '   ');
    RAISE EXCEPTION 'FALLO: se aceptó una corrección sin motivo';
  EXCEPTION
    WHEN check_violation THEN RAISE NOTICE 'OK · sin motivo no hay corrección';
  END;
END $$;

-- ══════════════════════════════════════════════════════════════════
-- 2 · Dos pacientes no pueden ocupar la misma posición
-- ══════════════════════════════════════════════════════════════════

INSERT INTO paciente (id, codigo, institucion_codigo, edad, sexo,
                      enrolado_por, dispositivo_id, enrolado_en)
  VALUES ('00000000-0000-4000-8000-000000000102', 'HC-002', 'HC',
          54, 'femenino', '00000000-0000-4000-8000-000000000001',
          '00000000-0000-4000-8000-0000000000d2', now());

INSERT INTO asignacion (secuencia_etiqueta, posicion, protocolo, paciente_id,
                        dispositivo_id, asignado_en)
  VALUES ('prueba', 1, 'a', '00000000-0000-4000-8000-000000000101',
          '00000000-0000-4000-8000-0000000000d1', now());

DO $$
BEGIN
  BEGIN
    -- El segundo dispositivo, sin conexión, creyó que le tocaba la 1.
    INSERT INTO asignacion (secuencia_etiqueta, posicion, protocolo, paciente_id,
                            dispositivo_id, asignado_en)
      VALUES ('prueba', 1, 'a',
              '00000000-0000-4000-8000-000000000102',
              '00000000-0000-4000-8000-0000000000d2', now());
    RAISE EXCEPTION 'FALLO: dos pacientes ocuparon la misma posición';
  EXCEPTION
    WHEN unique_violation THEN
      RAISE NOTICE 'OK · la colisión de posiciones se detecta al sincronizar';
  END;
END $$;

-- ══════════════════════════════════════════════════════════════════
-- 3 · La asignación tiene que coincidir con la secuencia
-- ══════════════════════════════════════════════════════════════════

DO $$
BEGIN
  BEGIN
    -- La posición 2 de '0101010101' es un 1, o sea rama B. Aquí se intenta A.
    INSERT INTO asignacion (secuencia_etiqueta, posicion, protocolo, paciente_id,
                            dispositivo_id, asignado_en)
      VALUES ('prueba', 2, 'a',
              '00000000-0000-4000-8000-000000000102',
              '00000000-0000-4000-8000-0000000000d2', now());
    RAISE EXCEPTION 'FALLO: se aceptó una asignación que contradice la secuencia';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FALLO%' THEN RAISE; END IF;
    RAISE NOTICE 'OK · una asignación incoherente con la secuencia se rechaza';
  END;

  BEGIN
    INSERT INTO asignacion (secuencia_etiqueta, posicion, protocolo, paciente_id,
                            dispositivo_id, asignado_en)
      VALUES ('prueba', 99, 'a',
              '00000000-0000-4000-8000-000000000102',
              '00000000-0000-4000-8000-0000000000d2', now());
    RAISE EXCEPTION 'FALLO: se aceptó una posición fuera de la secuencia';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FALLO%' THEN RAISE; END IF;
    RAISE NOTICE 'OK · una posición fuera de la secuencia se rechaza';
  END;
END $$;

-- La correcta sí entra.
INSERT INTO asignacion (secuencia_etiqueta, posicion, protocolo, paciente_id,
                        dispositivo_id, asignado_en)
  VALUES ('prueba', 2, 'b', '00000000-0000-4000-8000-000000000102',
          '00000000-0000-4000-8000-0000000000d2', now());

-- ══════════════════════════════════════════════════════════════════
-- 4 · Los tramos de secuencia no se pueden solapar
-- ══════════════════════════════════════════════════════════════════

INSERT INTO secuencia_rango (secuencia_etiqueta, dispositivo_id,
                             institucion_codigo, tramo)
  VALUES ('prueba', '00000000-0000-4000-8000-0000000000d1', 'HC', '[1,50)');

DO $$
BEGIN
  BEGIN
    INSERT INTO secuencia_rango (secuencia_etiqueta, dispositivo_id,
                                 institucion_codigo, tramo)
      VALUES ('prueba', '00000000-0000-4000-8000-0000000000d2', 'HC', '[40,90)');
    RAISE EXCEPTION 'FALLO: dos dispositivos recibieron tramos solapados';
  EXCEPTION
    WHEN exclusion_violation THEN
      RAISE NOTICE 'OK · los tramos de secuencia no se solapan';
  END;
END $$;

INSERT INTO secuencia_rango (secuencia_etiqueta, dispositivo_id,
                             institucion_codigo, tramo)
  VALUES ('prueba', '00000000-0000-4000-8000-0000000000d2', 'HC', '[50,90)');

-- ══════════════════════════════════════════════════════════════════
-- 5 · Los valores clínicos son solo-añadir
-- ══════════════════════════════════════════════════════════════════

INSERT INTO evento (id, paciente_id, tipo, ocurrencia, fecha_ocurrencia,
                    institucion_codigo, recolector_id, dispositivo_id,
                    fecha_captura)
  VALUES ('00000000-0000-4000-8000-0000000000e1',
          '00000000-0000-4000-8000-000000000101',
          'prueba_ventilacion_espontanea', 1, DATE '2026-08-14', 'HC',
          '00000000-0000-4000-8000-000000000001',
          '00000000-0000-4000-8000-0000000000d1', now());

INSERT INTO evento_valor (evento_id, campo, version, tipo, valor, capturado_en,
                          autor_id)
  VALUES ('00000000-0000-4000-8000-0000000000e1', 'fr_inicio', 1, 'numero', '92',
          now(), '00000000-0000-4000-8000-000000000001'),
         ('00000000-0000-4000-8000-0000000000e1', 'fr_inicio', 2, 'numero', '29',
          now(), '00000000-0000-4000-8000-000000000001');

DO $$
DECLARE
  vigente TEXT;
  versiones INTEGER;
BEGIN
  BEGIN
    UPDATE evento_valor SET valor = '99';
    RAISE EXCEPTION 'FALLO: se pudo sobrescribir un valor clínico';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FALLO%' THEN RAISE; END IF;
  END;

  SELECT valor INTO vigente FROM evento_valor_vigente
    WHERE evento_id = '00000000-0000-4000-8000-0000000000e1'
      AND campo = 'fr_inicio';
  IF vigente <> '29' THEN
    RAISE EXCEPTION 'FALLO: el valor vigente debería ser la última versión';
  END IF;

  SELECT count(*) INTO versiones FROM evento_valor
    WHERE evento_id = '00000000-0000-4000-8000-0000000000e1';
  IF versiones <> 2 THEN
    RAISE EXCEPTION 'FALLO: la versión anterior se perdió';
  END IF;

  RAISE NOTICE 'OK · corregir añade versión y conserva la anterior';
END $$;

-- ══════════════════════════════════════════════════════════════════
-- 6 · El analista no puede leer la identidad
-- ══════════════════════════════════════════════════════════════════

INSERT INTO identidad (paciente_id, nombre, numero_historia_clinica,
                       telefono_principal)
  VALUES ('00000000-0000-4000-8000-000000000101',
          'Paciente de Prueba', 'HC-9999', '5 000 0000');

DO $$
DECLARE
  filas INTEGER;
BEGIN
  SET LOCAL ROLE sivap_analista;

  BEGIN
    PERFORM * FROM identidad;
    RESET ROLE;
    RAISE EXCEPTION 'FALLO: el analista pudo leer la identidad de los pacientes';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE 'OK · el analista no accede a la identidad';
    WHEN raise_exception THEN
      RESET ROLE;
      RAISE;
  END;

  -- Y sí puede leer el dataset clínico, que es su trabajo.
  SET LOCAL ROLE sivap_analista;
  SELECT count(*) INTO filas FROM dataset_clinico;
  RESET ROLE;

  IF filas < 1 THEN
    RAISE EXCEPTION 'FALLO: el dataset clínico salió vacío';
  END IF;
  RAISE NOTICE 'OK · el analista lee el dataset clínico (% filas)', filas;
END $$;

-- ══════════════════════════════════════════════════════════════════
-- 7 · El dataset clínico sale ciego y sin identidad
-- ══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  columnas TEXT[];
BEGIN
  SELECT array_agg(column_name::text ORDER BY ordinal_position)
    INTO columnas
  FROM information_schema.columns WHERE table_name = 'dataset_clinico';

  IF columnas && ARRAY['nombre', 'numero_historia_clinica',
                       'telefono_principal', 'telefono_secundario'] THEN
    RAISE EXCEPTION 'FALLO: el dataset clínico expone identidad';
  END IF;

  IF NOT ('rama' = ANY(columnas)) THEN
    RAISE EXCEPTION 'FALLO: el dataset no lleva la rama';
  END IF;

  RAISE NOTICE 'OK · el dataset clínico va sin identidad y con la rama en A/B';
END $$;

-- ══════════════════════════════════════════════════════════════════
-- 8 · Un paciente aleatorizado no se borra
-- ══════════════════════════════════════════════════════════════════

DO $$
BEGIN
  BEGIN
    DELETE FROM paciente
      WHERE id = '00000000-0000-4000-8000-000000000101';
    RAISE EXCEPTION 'FALLO: se pudo borrar un paciente ya aleatorizado';
  EXCEPTION
    WHEN foreign_key_violation THEN
      RAISE NOTICE 'OK · un paciente aleatorizado no se borra';
  END;
END $$;

-- ══════════════════════════════════════════════════════════════════
-- 9 · Solo una secuencia activa, un coordinador y una definición activa
-- ══════════════════════════════════════════════════════════════════

DO $$
BEGIN
  BEGIN
    INSERT INTO secuencia (etiqueta, origen, codigo_binario, generada_en, activa)
      VALUES ('otra', 'cargada', '1010', now(), TRUE);
    RAISE EXCEPTION 'FALLO: se aceptaron dos secuencias activas';
  EXCEPTION
    WHEN unique_violation THEN RAISE NOTICE 'OK · una sola secuencia activa';
  END;

  BEGIN
    INSERT INTO institucion (codigo, nombre, coordinador)
      VALUES ('IC', 'Otro centro', TRUE);
    RAISE EXCEPTION 'FALLO: se aceptaron dos centros coordinadores';
  EXCEPTION
    WHEN unique_violation THEN RAISE NOTICE 'OK · un solo centro coordinador';
  END;

  BEGIN
    INSERT INTO institucion (codigo, nombre, cei_aprobado)
      VALUES ('IC', 'Otro centro', TRUE);
    RAISE EXCEPTION 'FALLO: se aprobó un CEI sin código ni fecha';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'OK · la aprobación del CEI exige código y fecha';
  END;
END $$;

ROLLBACK;

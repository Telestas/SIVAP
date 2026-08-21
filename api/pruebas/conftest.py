"""Andamiaje de las pruebas.

Corren contra un PostgreSQL de verdad, no contra un doble. El esquema hace valer
garantías que ningún simulacro reproduce —disparadores, restricciones de
solapamiento, privilegios por rol—, así que probar contra otra cosa daría una
confianza que no existe.

    docker run --rm -d --name sivap-pruebas -p 5433:5432 \
      -e POSTGRES_PASSWORD=pruebas postgres:16
    DATABASE_URL=postgresql://postgres:pruebas@localhost:5433/postgres \
      python -m pytest api/pruebas
"""

import os
import sys
import uuid
from pathlib import Path

import psycopg
from psycopg import pq
import pytest
from fastapi.testclient import TestClient

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))

from sivap import ajustes as mod_ajustes  # noqa: E402
from sivap.principal import app  # noqa: E402
from sivap.seguridad import cifrar_credencial  # noqa: E402

URL = os.environ.get('DATABASE_URL')

CONTRASENA = 'contrasena-de-prueba'

# Tablas que se vacían entre pruebas. `migracion` no: es el esquema, no datos.
#
# TRUNCATE y no DELETE a propósito: los disparadores de solo-inserción de
# `auditoria` y `evento_valor` rechazan cualquier DELETE, que es justamente lo
# que se quiere en producción.
TABLAS = ('sesion', 'evento_valor', 'evento', 'auditoria', 'consentimiento',
          'identidad', 'asignacion', 'paciente', 'secuencia_rango', 'secuencia',
          'dispositivo', 'investigador_rol', 'investigador',
          'definicion_formulario', 'institucion', 'lote_sincronizacion')


def _correr(con: psycopg.Connection, sql: str, origen: str) -> None:
    """Ejecuta un archivo entero.

    Por el protocolo simple de libpq, no por `execute`: las migraciones traen
    varias sentencias y funciones con `$$`, y el protocolo extendido solo admite
    una sentencia por llamada. Así tampoco hace falta tener `psql` instalado.
    """
    resultado = con.pgconn.exec_(sql.encode())
    if resultado.status not in (pq.ExecStatus.COMMAND_OK,
                                pq.ExecStatus.TUPLES_OK):
        raise RuntimeError(f'{origen}: {resultado.error_message.decode()}')


def _migrar() -> None:
    with psycopg.connect(URL, autocommit=True) as con:
        con.execute('DROP SCHEMA public CASCADE; CREATE SCHEMA public;')
        for rol in ('sivap_api', 'sivap_analista'):
            con.execute(f'DROP ROLE IF EXISTS {rol};')
        for sql in sorted((RAIZ / 'migraciones').glob('*.sql')):
            _correr(con, sql.read_text(), sql.name)


@pytest.fixture(scope='session', autouse=True)
def base_de_datos():
    if not URL:
        pytest.skip('Sin DATABASE_URL: estas pruebas necesitan PostgreSQL.')
    mod_ajustes.reiniciar()
    _migrar()
    yield


@pytest.fixture(autouse=True)
def limpiar():
    yield
    with psycopg.connect(URL, autocommit=True) as con:
        con.execute(f'TRUNCATE {", ".join(TABLAS)} RESTART IDENTITY CASCADE;')


@pytest.fixture
def cliente():
    with TestClient(app) as c:
        yield c


@pytest.fixture
def con():
    with psycopg.connect(URL, autocommit=True) as c:
        yield c


# ── Constructores de datos ────────────────────────────────────────

@pytest.fixture
def centro(con):
    def crear(codigo='HC', nombre='Centro de prueba', coordinador=True,
              cei_aprobado=False):
        con.execute(
            'INSERT INTO institucion (codigo, nombre, coordinador,'
            ' cei_aprobado, cei_codigo, cei_aprobado_en)'
            ' VALUES (%s, %s, %s, %s, %s, %s)',
            (codigo, nombre, coordinador, cei_aprobado,
             'CEI-1' if cei_aprobado else None,
             '2026-01-01' if cei_aprobado else None))
        return codigo
    return crear


@pytest.fixture
def investigador(con, centro):
    creados = {'centros': set()}

    def crear(usuario='prueba', roles=('reclutador',), institucion='HC',
              nombre='Dra. Prueba', activo=True):
        if institucion not in creados['centros']:
            existe = con.execute(
                'SELECT 1 FROM institucion WHERE codigo = %s',
                (institucion,)).fetchone()
            if not existe:
                centro(codigo=institucion, coordinador=(institucion == 'HC'))
            creados['centros'].add(institucion)

        ident = uuid.uuid4()
        con.execute(
            'INSERT INTO investigador (id, usuario, nombre, credencial_hash,'
            ' institucion_codigo, activo) VALUES (%s, %s, %s, %s, %s, %s)',
            (ident, usuario, nombre, cifrar_credencial(CONTRASENA),
             institucion, activo))
        for rol in roles:
            con.execute('INSERT INTO investigador_rol (investigador_id, rol)'
                        ' VALUES (%s, %s)', (ident, rol))
        return ident
    return crear


@pytest.fixture
def sesion(cliente, investigador):
    def abrir(usuario='prueba', roles=('reclutador',), institucion='HC',
              **extra):
        investigador(usuario=usuario, roles=roles, institucion=institucion,
                     **extra)
        r = cliente.post('/api/sesion',
                         json={'usuario': usuario, 'contrasena': CONTRASENA})
        assert r.status_code == 200, r.text
        token = r.json()['token']
        return {'Authorization': f'Bearer {token}'}
    return abrir


@pytest.fixture
def secuencia(con):
    def crear(codigo='0101010101' * 10, etiqueta='prueba'):
        con.execute(
            'INSERT INTO secuencia (etiqueta, origen, codigo_binario,'
            ' generada_en, activa) VALUES (%s, %s, %s, now(), TRUE)',
            (etiqueta, 'generada_por_computadora', codigo))
        return etiqueta
    return crear


@pytest.fixture
def consumir_posiciones(con):
    """Simula pacientes ya enrolados en unas posiciones de la secuencia."""

    def consumir(dispositivo_id, etiqueta, desde, hasta, institucion='HC',
                 investigador_id=None):
        if investigador_id is None:
            investigador_id = con.execute(
                'SELECT id FROM investigador LIMIT 1').fetchone()[0]
        codigo = con.execute(
            'SELECT codigo_binario FROM secuencia WHERE etiqueta = %s',
            (etiqueta,)).fetchone()[0]
        for pos in range(desde, hasta):
            paciente = uuid.uuid4()
            con.execute(
                'INSERT INTO paciente (id, codigo, institucion_codigo, edad,'
                ' sexo, enrolado_por, dispositivo_id, enrolado_en)'
                ' VALUES (%s, %s, %s, 60, %s, %s, %s, now())',
                (paciente, f'{institucion}-{pos:03d}', institucion,
                 'masculino', investigador_id, dispositivo_id))
            con.execute(
                'INSERT INTO asignacion (secuencia_etiqueta, posicion,'
                ' protocolo, paciente_id, dispositivo_id, asignado_en)'
                ' VALUES (%s, %s, %s, %s, %s, now())',
                (etiqueta, pos, 'b' if codigo[pos - 1] == '1' else 'a',
                 paciente, dispositivo_id))
    return consumir

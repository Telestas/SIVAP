"""Acceso a la base de datos.

Una conexión por petición, sin agrupación. Para el volumen de este estudio
—tres centros, una decena de investigadores— abrir una conexión cuesta unos
milisegundos y ahorra una dependencia y un modo de fallo. Si algún día el
volumen lo pide, se pone un `psycopg_pool` aquí y no se toca nada más.
"""

from contextlib import contextmanager
from typing import Any, Iterator

import psycopg
from psycopg.rows import dict_row

from .ajustes import ajustes


@contextmanager
def conexion() -> Iterator[psycopg.Connection]:
    """Conexión con transacción: confirma al salir, deshace si algo falla."""
    with psycopg.connect(ajustes().url_base_datos, row_factory=dict_row) as con:
        yield con


def uno(con: psycopg.Connection, sql: str,
        params: tuple = ()) -> dict[str, Any] | None:
    with con.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchone()


def varios(con: psycopg.Connection, sql: str,
           params: tuple = ()) -> list[dict[str, Any]]:
    with con.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def ejecutar(con: psycopg.Connection, sql: str, params: tuple = ()) -> None:
    with con.cursor() as cur:
        cur.execute(sql, params)

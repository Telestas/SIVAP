from fastapi import APIRouter

from .. import bd

router = APIRouter(tags=['salud'])


@router.get('/salud')
def salud() -> dict:
    """Comprobación de vida, para el orquestador y para diagnosticar."""
    with bd.conexion() as con:
        version = bd.uno(con, 'SELECT max(version) AS v FROM migracion') \
            if _hay_tabla_migraciones(con) else None
        bd.uno(con, 'SELECT 1 AS ok')
    return {
        'estado': 'ok',
        'esquema': version['v'] if version else 'sin registro de migraciones',
    }


def _hay_tabla_migraciones(con) -> bool:
    fila = bd.uno(
        con,
        "SELECT to_regclass('public.migracion') IS NOT NULL AS existe",
    )
    return bool(fila and fila['existe'])

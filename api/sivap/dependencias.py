"""Autenticación como dependencia de FastAPI."""

from datetime import datetime, timezone
from typing import Annotated, Any

from fastapi import Depends, Header, HTTPException, status

from . import bd
from .seguridad import huella

SIN_AUTORIZAR = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail='Sesión no válida o caducada.',
    headers={'WWW-Authenticate': 'Bearer'},
)


def investigador_actual(
    authorization: Annotated[str | None, Header()] = None,
) -> dict[str, Any]:
    """Resuelve el investigador de la sesión, o corta con 401."""
    if not authorization or not authorization.lower().startswith('bearer '):
        raise SIN_AUTORIZAR

    token = authorization.split(' ', 1)[1].strip()
    if not token:
        raise SIN_AUTORIZAR

    with bd.conexion() as con:
        fila = bd.uno(
            con,
            """
            SELECT s.investigador_id, s.dispositivo_id, s.expira_en,
                   s.revocada_en, i.usuario, i.nombre, i.institucion_codigo,
                   i.activo
            FROM sesion s
            JOIN investigador i ON i.id = s.investigador_id
            WHERE s.token_hash = %s
            """,
            (huella(token),),
        )
        if fila is None or fila['revocada_en'] is not None:
            raise SIN_AUTORIZAR
        if fila['expira_en'] <= datetime.now(timezone.utc):
            raise SIN_AUTORIZAR
        if not fila['activo']:
            # Dar de baja a alguien tiene que cortarle el acceso en el acto, no
            # cuando le caduque el token dentro de un mes.
            raise SIN_AUTORIZAR

        fila['roles'] = [
            r['rol'] for r in bd.varios(
                con,
                'SELECT rol FROM investigador_rol WHERE investigador_id = %s'
                ' ORDER BY rol',
                (fila['investigador_id'],),
            )
        ]
    return fila


Autenticado = Annotated[dict[str, Any], Depends(investigador_actual)]


def exigir_rol(*roles: str):
    """Restringe una ruta a ciertas funciones del ensayo.

    **Restricción CLAUDE.md §11**: ninguna ruta sin declarar explícitamente qué
    función puede invocarla. Esta dependencia es la forma de declararlo.
    """

    def comprobar(quien: Autenticado) -> dict[str, Any]:
        if not set(roles) & set(quien['roles']):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f'Esta operación corresponde a: {", ".join(roles)}.',
            )
        return quien

    return comprobar

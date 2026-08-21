from typing import Annotated

from fastapi import APIRouter, Header, HTTPException, status

from .. import bd
from ..ajustes import ajustes
from ..dependencias import Autenticado
from ..modelos import Investigador, PeticionSesion, RespuestaSesion
from ..seguridad import (caducidad, cifrar_credencial, huella, necesita_rehash,
                         nuevo_token, verificar_credencial)

router = APIRouter(prefix='/sesion', tags=['sesión'])


@router.post('', response_model=RespuestaSesion)
def abrir(peticion: PeticionSesion) -> RespuestaSesion:
    """Abre una sesión de sincronización.

    Esto **no** es el acceso a la app: la app se abre sin conexión validando la
    credencial guardada en el dispositivo (CLAUDE.md §12). El token que se
    entrega aquí solo sirve para hablar con el servidor.
    """
    with bd.conexion() as con:
        fila = bd.uno(
            con,
            """
            SELECT id, usuario, nombre, credencial_hash, institucion_codigo,
                   activo
            FROM investigador WHERE usuario = %s
            """,
            (peticion.usuario,),
        )

        # Mismo error y mismo coste para «usuario inexistente» y «contraseña
        # incorrecta»: distinguirlos permitiría averiguar qué usuarios existen.
        valido = fila is not None and verificar_credencial(
            fila['credencial_hash'], peticion.contrasena)
        if not valido or not fila['activo']:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail='Usuario o contraseña incorrectos.',
            )

        # Si los parámetros de Argon2 subieron desde que se guardó, se
        # aprovecha que tenemos la contraseña en memoria para rehacerlo.
        if necesita_rehash(fila['credencial_hash']):
            bd.ejecutar(
                con, 'UPDATE investigador SET credencial_hash = %s WHERE id = %s',
                (cifrar_credencial(peticion.contrasena), fila['id']))

        if peticion.dispositivo_id is not None:
            _comprobar_dispositivo(con, peticion.dispositivo_id, fila['id'])

        token, hash_token = nuevo_token()
        expira = caducidad(ajustes().horas_sesion)
        bd.ejecutar(
            con,
            'INSERT INTO sesion (token_hash, investigador_id, dispositivo_id,'
            ' expira_en) VALUES (%s, %s, %s, %s)',
            (hash_token, fila['id'], peticion.dispositivo_id, expira),
        )

        roles = [r['rol'] for r in bd.varios(
            con,
            'SELECT rol FROM investigador_rol WHERE investigador_id = %s'
            ' ORDER BY rol',
            (fila['id'],))]

    return RespuestaSesion(
        token=token,
        expira_en=expira,
        investigador=Investigador(
            id=fila['id'],
            usuario=fila['usuario'],
            nombre=fila['nombre'],
            institucion=fila['institucion_codigo'],
            roles=roles,
        ),
    )


def _comprobar_dispositivo(con, dispositivo_id, investigador_id) -> None:
    fila = bd.uno(con, 'SELECT investigador_id FROM dispositivo WHERE id = %s',
                  (dispositivo_id,))
    if fila is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='El dispositivo no está registrado.')
    if fila['investigador_id'] != investigador_id:
        # Un dispositivo pertenece a una persona. Si dos comparten teléfono, se
        # registra dos veces con identificadores distintos: si no, no habría
        # forma de saber quién capturó qué.
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='El dispositivo está registrado a nombre de otra persona.')


@router.delete('', status_code=status.HTTP_204_NO_CONTENT)
def cerrar(quien: Autenticado,
           authorization: Annotated[str, Header()] = '') -> None:
    """Revoca la sesión en curso.

    Se revoca, no se borra: saber que una sesión existió y cuándo se cortó es
    parte de poder reconstruir qué pasó.
    """
    with bd.conexion() as con:
        bd.ejecutar(
            con,
            'UPDATE sesion SET revocada_en = now()'
            ' WHERE investigador_id = %s AND revocada_en IS NULL'
            '   AND token_hash = %s',
            (quien['investigador_id'], huella(authorization.split(' ')[-1])),
        )

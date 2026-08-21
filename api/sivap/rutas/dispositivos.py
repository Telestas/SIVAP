from fastapi import APIRouter, Depends, HTTPException, status

from .. import bd
from ..ajustes import ajustes
from ..dependencias import Autenticado, exigir_rol
from ..modelos import Dispositivo, PeticionDispositivo, Tramo

router = APIRouter(prefix='/dispositivos', tags=['dispositivos'])

# Quién puede pedir tramo de secuencia: solo quien enrola. Es la restricción
# CLAUDE.md §11 —cada ruta declara su función— y además tiene sentido
# metodológico: el aplicador y el evaluador no asignan ramas.
PUEDE_ENROLAR = exigir_rol('reclutador', 'investigador_principal')


@router.post('', response_model=Dispositivo,
             status_code=status.HTTP_201_CREATED)
def registrar(peticion: PeticionDispositivo,
              quien: Autenticado) -> Dispositivo:
    """Registra el dispositivo, o actualiza su etiqueta si ya existía.

    El identificador lo trae el dispositivo: tiene que poder generarse sin
    conexión, igual que los de pacientes y eventos.
    """
    with bd.conexion() as con:
        existente = bd.uno(
            con, 'SELECT investigador_id FROM dispositivo WHERE id = %s',
            (peticion.id,))

        if existente and existente['investigador_id'] != quien['investigador_id']:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail='Ese dispositivo ya está registrado por otra persona.')

        fila = bd.uno(
            con,
            """
            INSERT INTO dispositivo (id, investigador_id, etiqueta)
                 VALUES (%s, %s, %s)
            ON CONFLICT (id) DO UPDATE SET etiqueta = EXCLUDED.etiqueta
              RETURNING id, etiqueta, investigador_id, registrado_en,
                        ultima_sincronizacion
            """,
            (peticion.id, quien['investigador_id'], peticion.etiqueta),
        )
    return Dispositivo(**fila)


@router.post('/{dispositivo_id}/tramo', response_model=Tramo,
             dependencies=[Depends(PUEDE_ENROLAR)])
def tramo(dispositivo_id: str, quien: Autenticado) -> Tramo:
    """Entrega al dispositivo su tramo de la secuencia de aleatorización.

    **Esto es lo que hace posible enrolar sin conexión sin romper el estudio.**
    Si todos los dispositivos consumieran de la misma lista, dos que estén sin
    cobertura asignarían ambos la posición siguiente y, al sincronizar, dos
    pacientes reclamarían la misma. Cada dispositivo recibe un tramo propio,
    disjunto de los demás, y la base rechaza cualquier solapamiento.

    Es el equivalente digital de los sobres sellados y numerados: cada sobre lo
    abre uno solo porque nadie más lo tiene.

    Devuelve el tramo en curso mientras le queden posiciones. Solo entrega uno
    nuevo cuando el anterior se agotó, para no repartir la secuencia entre
    dispositivos que no la están usando.
    """
    with bd.conexion() as con:
        _comprobar_propiedad(con, dispositivo_id, quien)

        secuencia = bd.uno(
            con,
            'SELECT etiqueta, codigo_binario, longitud FROM secuencia'
            ' WHERE activa LIMIT 1')
        if secuencia is None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail='El estudio no tiene una secuencia de aleatorización '
                       'activa. Cárguela antes de repartir tramos.')

        # Bloquea la secuencia mientras se calcula el siguiente hueco: si dos
        # dispositivos piden tramo a la vez, uno espera al otro en vez de que
        # ambos lean el mismo final.
        bd.uno(con, 'SELECT etiqueta FROM secuencia WHERE etiqueta = %s'
                    ' FOR UPDATE', (secuencia['etiqueta'],))

        actual = _tramo_con_posiciones_libres(con, dispositivo_id,
                                              secuencia['etiqueta'])
        if actual is None:
            actual = _asignar_tramo(con, dispositivo_id, quien, secuencia)

        desde, hasta = actual['desde'], actual['hasta']
        consumidas = _consumidas(con, secuencia['etiqueta'], desde, hasta)

    return Tramo(
        desde=desde,
        hasta=hasta,
        asignado_en=actual['asignado_en'],
        consumidas=consumidas,
        # Solo los bits de su tramo. El dispositivo nunca recibe la secuencia
        # completa: si se pierde el teléfono, se compromete su tramo, no el
        # ensayo entero.
        codigo_binario=secuencia['codigo_binario'][desde - 1:hasta - 1],
    )


def _comprobar_propiedad(con, dispositivo_id, quien) -> None:
    fila = bd.uno(con, 'SELECT investigador_id FROM dispositivo WHERE id = %s',
                  (dispositivo_id,))
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail='Dispositivo no registrado.')
    if fila['investigador_id'] != quien['investigador_id']:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Ese dispositivo no es suyo.')


def _tramo_con_posiciones_libres(con, dispositivo_id, etiqueta):
    return bd.uno(
        con,
        """
        SELECT lower(r.tramo) AS desde, upper(r.tramo) AS hasta, r.asignado_en
          FROM secuencia_rango r
         WHERE r.dispositivo_id = %s AND r.secuencia_etiqueta = %s
           AND (SELECT count(*) FROM asignacion a
                 WHERE a.secuencia_etiqueta = r.secuencia_etiqueta
                   AND a.posicion >= lower(r.tramo)
                   AND a.posicion <  upper(r.tramo))
               < (upper(r.tramo) - lower(r.tramo))
         ORDER BY lower(r.tramo)
         LIMIT 1
        """,
        (dispositivo_id, etiqueta),
    )


def _asignar_tramo(con, dispositivo_id, quien, secuencia):
    siguiente = bd.uno(
        con,
        'SELECT COALESCE(max(upper(tramo)), 1) AS inicio FROM secuencia_rango'
        ' WHERE secuencia_etiqueta = %s',
        (secuencia['etiqueta'],))['inicio']

    fin = min(siguiente + ajustes().tamano_tramo, secuencia['longitud'] + 1)
    if siguiente > secuencia['longitud']:
        # Enrolar más allá de la secuencia prevista es un error del estudio, no
        # algo que el servidor deba improvisar.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='La secuencia de aleatorización está agotada. Genere una '
                   'nueva antes de seguir enrolando.')

    return bd.uno(
        con,
        """
        INSERT INTO secuencia_rango (secuencia_etiqueta, dispositivo_id,
                                     institucion_codigo, tramo)
             VALUES (%s, %s, %s, int4range(%s, %s))
          RETURNING lower(tramo) AS desde, upper(tramo) AS hasta, asignado_en
        """,
        (secuencia['etiqueta'], dispositivo_id, quien['institucion_codigo'],
         siguiente, fin),
    )


def _consumidas(con, etiqueta, desde, hasta) -> int:
    return bd.uno(
        con,
        'SELECT count(*) AS n FROM asignacion WHERE secuencia_etiqueta = %s'
        ' AND posicion >= %s AND posicion < %s',
        (etiqueta, desde, hasta))['n']

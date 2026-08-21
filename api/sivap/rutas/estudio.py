from fastapi import APIRouter

from .. import bd
from ..dependencias import Autenticado
from ..modelos import ConfiguracionEstudio, Institucion

router = APIRouter(prefix='/estudio', tags=['estudio'])


@router.get('', response_model=ConfiguracionEstudio)
def configuracion(quien: Autenticado) -> ConfiguracionEstudio:
    """Configuración que el dispositivo descarga y guarda para trabajar sin
    conexión.

    Aquí viaja la **definición de formularios** (CLAUDE.md §5): ajustar el
    protocolo es publicar una versión nueva de esta definición, no recompilar la
    app ni repartir un APK.

    Lo que NO viaja es la secuencia de aleatorización. Se entrega por tramos, en
    `/dispositivos/{id}/tramo`, y cada dispositivo solo ve el suyo.
    """
    with bd.conexion() as con:
        instituciones = [
            Institucion(**fila) for fila in bd.varios(
                con,
                'SELECT codigo, nombre, coordinador, cei_aprobado'
                ' FROM institucion ORDER BY coordinador DESC, codigo')
        ]

        definicion = bd.uno(
            con,
            'SELECT version, definicion FROM definicion_formulario'
            ' WHERE activa LIMIT 1')

        secuencia = bd.uno(
            con,
            'SELECT etiqueta, longitud FROM secuencia WHERE activa LIMIT 1')

    return ConfiguracionEstudio(
        instituciones=instituciones,
        definicion_formulario_version=definicion['version'] if definicion else None,
        definicion_formulario=definicion['definicion'] if definicion else None,
        secuencia_etiqueta=secuencia['etiqueta'] if secuencia else None,
        secuencia_longitud=secuencia['longitud'] if secuencia else None,
        # Restricción CLAUDE.md §13. La aprobación es por centro: uno puede
        # empezar antes que otro, y el dispositivo tiene que saber en cuáles
        # puede enrolar de verdad.
        admite_pacientes_reales=any(i.cei_aprobado for i in instituciones),
    )

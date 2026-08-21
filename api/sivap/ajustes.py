"""Configuración, tomada del entorno.

Nada de esto lleva valor por defecto que sirva en producción: si falta la
cadena de conexión o la clave, el servicio no arranca. Un servidor que arranca
con una configuración a medias es peor que uno que no arranca, porque nadie se
entera hasta que hace falta.
"""

import os


class ErrorDeConfiguracion(RuntimeError):
    pass


def _obligatorio(nombre: str) -> str:
    valor = os.environ.get(nombre)
    if not valor:
        raise ErrorDeConfiguracion(
            f'Falta la variable de entorno {nombre}. Ver deploy/.env.example.')
    return valor


def _entero(nombre: str, por_defecto: int) -> int:
    return int(os.environ.get(nombre, por_defecto))


class Ajustes:
    def __init__(self) -> None:
        self.url_base_datos = _obligatorio('DATABASE_URL')
        self.entorno = os.environ.get('SIVAP_ENTORNO', 'desarrollo')

        # Cuántas posiciones de la secuencia recibe cada dispositivo.
        #
        # Es el equivalente digital de cuántos sobres numerados se le dan a cada
        # centro. Un tramo corto obliga a pedir otro a menudo —y hay que tener
        # conexión para pedirlo—; uno largo desperdicia más posiciones si el
        # teléfono se pierde, porque ese tramo queda quemado.
        self.tamano_tramo = _entero('SIVAP_TAMANO_TRAMO', 25)

        # Larga a propósito: un teléfono puede pasar semanas sin cobertura.
        self.horas_sesion = _entero('SIVAP_HORAS_SESION', 720)

    @property
    def es_produccion(self) -> bool:
        return self.entorno == 'produccion'


_ajustes: Ajustes | None = None


def ajustes() -> Ajustes:
    global _ajustes
    if _ajustes is None:
        _ajustes = Ajustes()
    return _ajustes


def reiniciar() -> None:
    """Olvida la configuración cargada. Solo para las pruebas."""
    global _ajustes
    _ajustes = None

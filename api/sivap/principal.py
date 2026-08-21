"""Aplicación FastAPI del ensayo LIVERE."""

from fastapi import FastAPI

from .rutas import dispositivos, estudio, salud, sesion

app = FastAPI(
    title='SIVAP — api del ensayo LIVERE',
    version='0.1.0',
    description=(
        'Servicio central del ensayo. La captura de datos NO depende de él: '
        'la app trabaja sin conexión y esto solo consolida (CLAUDE.md §12).'
    ),
    # Sin documentación interactiva en producción: describe la superficie
    # completa de la api a quien no debería verla.
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)

for router in (salud.router, sesion.router, dispositivos.router, estudio.router):
    app.include_router(router, prefix='/api')


def crear_app(con_documentacion: bool = False) -> FastAPI:
    """Instancia con documentación, para desarrollo y pruebas."""
    if not con_documentacion:
        return app
    app.openapi_url = '/api/openapi.json'
    app.docs_url = '/api/docs'
    return app

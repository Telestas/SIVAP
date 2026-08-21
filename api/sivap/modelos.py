"""Formas de entrada y salida de la api."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class PeticionSesion(BaseModel):
    usuario: str = Field(min_length=1, max_length=64)
    contrasena: str = Field(min_length=1, max_length=256)
    dispositivo_id: UUID | None = None


class Investigador(BaseModel):
    id: UUID
    usuario: str
    nombre: str
    institucion: str
    roles: list[str]


class RespuestaSesion(BaseModel):
    token: str
    expira_en: datetime
    investigador: Investigador


class PeticionDispositivo(BaseModel):
    # El identificador lo genera el dispositivo, no el servidor: tiene que poder
    # crearse sin conexión.
    id: UUID
    etiqueta: str = Field(min_length=1, max_length=80)


class Dispositivo(BaseModel):
    id: UUID
    etiqueta: str
    investigador_id: UUID
    registrado_en: datetime
    ultima_sincronizacion: datetime | None


class Tramo(BaseModel):
    """Un tramo de la secuencia de aleatorización, asignado a un dispositivo."""

    desde: int
    hasta: int
    """Exclusivo: el tramo cubre `desde` .. `hasta - 1`."""

    asignado_en: datetime
    consumidas: int

    codigo_binario: str
    """Las ramas **de este tramo y solo de este tramo**.

    `0` = Protocolo A, `1` = Protocolo B. El dispositivo nunca recibe la
    secuencia completa del estudio: si se pierde el teléfono, lo que se
    compromete es su tramo, no el ensayo entero.
    """


class Institucion(BaseModel):
    codigo: str
    nombre: str
    coordinador: bool
    cei_aprobado: bool


class ConfiguracionEstudio(BaseModel):
    instituciones: list[Institucion]
    definicion_formulario_version: str | None
    definicion_formulario: dict | None
    secuencia_etiqueta: str | None
    secuencia_longitud: int | None
    admite_pacientes_reales: bool
    """Verdadero solo si algún centro tiene la aprobación del CEI."""

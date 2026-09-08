"""Formas de entrada y salida de la api."""

from datetime import date, datetime
from typing import Literal
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


# ══════════════════════════════════════════════════════════════════
# Sincronización
# ══════════════════════════════════════════════════════════════════
#
# Lo que sube el dispositivo. Los tipos van como `Literal` y no como `str` a
# propósito: un valor que no existe en el enum de la base se rechaza aquí, con
# un mensaje que dice qué campo está mal, en vez de convertirse en un error de
# PostgreSQL a mitad del lote.

Sexo = Literal['masculino', 'femenino']

Protocolo = Literal['a', 'b']

# Los cinco módulos del Anexo 4 revisado. La lista tiene que coincidir con el
# enum `tipo_evento` del esquema (migración 003) y con `TipoEvento` de la app:
# es el mismo vocabulario en los tres sitios.
TipoEvento = Literal[
    'enrolamiento', 'cribado', 'prueba_ventilacion_espontanea', 'extubacion',
    'desenlaces', 'seguimiento_post_egreso',
]

TipoValor = Literal['numero', 'texto', 'booleano', 'fecha', 'lista']

EntidadAuditada = Literal['ficha', 'evento', 'consentimiento', 'usuario']


class Identidad(BaseModel):
    """Restricción CLAUDE.md §9: solo lo que el Anexo 4 exige, y nada más.

    Ni carné ni dirección. Si algún día aparece un campo nuevo aquí, tiene que
    poder justificarse ante el Comité de Ética.
    """

    nombre: str = Field(min_length=1, max_length=200)
    numero_historia_clinica: str = Field(min_length=1, max_length=64)
    telefono_principal: str = Field(min_length=1, max_length=32)
    telefono_secundario: str | None = Field(default=None, max_length=32)


class Asignacion(BaseModel):
    """La posición de la secuencia que consumió este paciente.

    La rama viene del dispositivo porque el dispositivo la decidió sin
    conexión, con el tramo que se le entregó. El servidor no se fía: un
    disparador comprueba contra la secuencia que la rama es la que tocaba en esa
    posición, y la clave primaria impide que dos pacientes ocupen la misma.
    """

    secuencia_etiqueta: str
    posicion: int = Field(ge=1)
    protocolo: Protocolo
    asignado_en: datetime


class PacienteEntrante(BaseModel):
    id: UUID
    codigo: str = Field(min_length=1, max_length=32)
    institucion_codigo: str
    edad: int = Field(ge=0, le=130)
    sexo: Sexo
    enrolado_en: datetime
    identidad: Identidad
    asignacion: Asignacion


class ConsentimientoEntrante(BaseModel):
    id: UUID
    paciente_id: UUID
    version_documento: str
    codigo_cei: str
    firmado_en: datetime
    testigo_id: UUID
    firma: dict


class ValorEntrante(BaseModel):
    campo: str = Field(min_length=1, max_length=120)
    tipo: TipoValor
    valor: str | None = None
    capturado_en: datetime | None = None
    """Si falta, se toma la fecha de captura del evento."""


class EventoEntrante(BaseModel):
    id: UUID
    paciente_id: UUID
    tipo: TipoEvento
    ocurrencia: int = Field(ge=1)
    fecha_ocurrencia: date
    institucion_codigo: str
    fecha_captura: datetime
    valores: list[ValorEntrante] = Field(default_factory=list)


class AuditoriaEntrante(BaseModel):
    id: UUID
    ocurrido_en: datetime
    entidad: EntidadAuditada
    entidad_id: UUID
    descripcion_objetivo: str
    campo: str
    valor_anterior: str | None = None
    valor_nuevo: str | None = None
    motivo: str = Field(min_length=1)


class Lote(BaseModel):
    """Un envío del dispositivo.

    `id` lo genera el dispositivo y es lo que hace el envío repetible: si la
    conexión se corta después de que el servidor guardara pero antes de que la
    respuesta llegara —que con esta conectividad va a pasar—, el dispositivo
    reenvía el mismo lote y recibe el mismo resultado, sin duplicar nada.
    """

    id: UUID
    dispositivo_id: UUID
    pacientes: list[PacienteEntrante] = Field(default_factory=list)
    consentimientos: list[ConsentimientoEntrante] = Field(default_factory=list)
    eventos: list[EventoEntrante] = Field(default_factory=list)
    auditoria: list[AuditoriaEntrante] = Field(default_factory=list)


class Rechazo(BaseModel):
    tipo: str
    """`paciente`, `consentimiento`, `evento`, `valor` o `auditoria`."""

    id: str
    motivo: str


class ResultadoLote(BaseModel):
    lote_id: UUID
    registros: int
    aceptados: int
    rechazados: int
    detalle: list[Rechazo]
    ya_recibido: bool = False
    """Verdadero si el lote ya se había procesado: se devuelve el resultado
    guardado y no se toca nada."""

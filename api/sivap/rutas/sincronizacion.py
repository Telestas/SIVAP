"""Recepción de lo que capturó un dispositivo.

Esta ruta es el único camino por el que los datos de campo llegan a la base
central. Tres decisiones la gobiernan, y conviene entenderlas antes de tocar
nada:

**Un registro malo no tumba el lote.** Cada registro entra en su propio punto de
guardado: lo que falla se rechaza con su motivo y lo demás se guarda. La
alternativa —todo o nada— significaría que un teléfono con un registro
problemático no consigue sincronizar nunca, y con esta conectividad eso no es
una hipótesis. La tabla `lote_sincronizacion` ya venía con `aceptados` y
`rechazados` por esto mismo.

**Reenviar un lote no duplica nada.** El dispositivo genera el identificador del
lote; si la conexión se corta después de guardar pero antes de que llegue la
respuesta, el reenvío devuelve el resultado guardado. Y cada registro es
idempotente por su cuenta, porque el dispositivo puede reagrupar lo pendiente en
lotes distintos.

**Una corrección no sobrescribe: añade una versión.** «Último gana» resuelve el
conflicto sin perder lo anterior, que es lo que se pregunta en una inspección.

El rechazo por registro cubre lo que la base rechaza. Un envío que ni siquiera
se puede leer —un tipo de evento que no existe, una fecha imposible— sí corta el
lote entero, con un 422: eso no es un dato de campo discutible, es la app
enviando algo que no debería existir, y conviene que se vea de golpe y no
diluido entre los rechazos.
"""

from typing import Any

import psycopg
from fastapi import APIRouter, Depends, status
from psycopg.types.json import Jsonb

from .. import bd
from ..dependencias import Autenticado, dispositivo_propio, exigir_rol
from ..modelos import (AuditoriaEntrante, ConsentimientoEntrante,
                       EventoEntrante, Lote, PacienteEntrante, Rechazo,
                       ResultadoLote)

router = APIRouter(prefix='/sincronizacion', tags=['sincronización'])


class Rechazado(Exception):
    """Un registro que el estudio no admite, por una regla que no es del
    esquema. Se trata igual que un error de la base: rechaza ese registro y
    deja pasar el resto."""


# Restricción CLAUDE.md §11: quién puede invocar esta ruta.
#
# Quien captura. El analista y el observador no suben datos —solo leen— y darles
# esta ruta les daría un camino para escribir en el estudio que su función no
# contempla.
PUEDE_SINCRONIZAR = exigir_rol('reclutador', 'aplicador',
                               'evaluador_desenlaces',
                               'investigador_principal')


@router.post('', response_model=ResultadoLote,
             dependencies=[Depends(PUEDE_SINCRONIZAR)],
             status_code=status.HTTP_200_OK)
def recibir(lote: Lote, quien: Autenticado) -> ResultadoLote:
    """Recibe un lote del dispositivo y devuelve qué entró y qué no."""
    with bd.conexion() as con:
        dispositivo_propio(con, lote.dispositivo_id, quien)

        # Se anota el contacto aunque el lote venga vacío o repetido: saber
        # cuándo se comunicó por última vez cada teléfono es lo que permite
        # notar que uno lleva tres semanas callado.
        bd.ejecutar(
            con,
            'UPDATE dispositivo SET ultima_sincronizacion = now()'
            ' WHERE id = %s', (lote.dispositivo_id,))

        previo = bd.uno(
            con,
            'SELECT registros, aceptados, rechazados, detalle'
            ' FROM lote_sincronizacion WHERE id = %s',
            (lote.id,))
        if previo is not None:
            return ResultadoLote(
                lote_id=lote.id,
                registros=previo['registros'],
                aceptados=previo['aceptados'],
                rechazados=previo['rechazados'],
                detalle=[Rechazo(**r) for r in (previo['detalle'] or [])],
                ya_recibido=True,
            )

        rechazos: list[Rechazo] = []
        aceptados = 0

        for paciente in lote.pacientes:
            aceptados += _guardar(con, rechazos, 'paciente', paciente.id,
                                  lambda: _paciente(con, paciente, lote, quien))

        for consentimiento in lote.consentimientos:
            aceptados += _guardar(
                con, rechazos, 'consentimiento', consentimiento.id,
                lambda: _consentimiento(con, consentimiento))

        for evento in lote.eventos:
            guardado = _guardar(con, rechazos, 'evento', evento.id,
                                lambda: _evento(con, evento, lote, quien))
            aceptados += guardado
            if guardado:
                # Los valores van uno a uno y después del evento: si uno de
                # ellos falla, el evento ya está y el resto de los valores
                # también. Perder el evento entero por un campo mal tipado
                # sería peor que quedarse sin ese campo.
                for valor in evento.valores:
                    aceptados += _guardar(
                        con, rechazos, 'valor',
                        f'{evento.id}/{valor.campo}',
                        lambda: _valor(con, evento, valor, quien))
            else:
                # Los valores de un evento que no entró se cuentan como
                # rechazados, no se callan. Si no, el diario diría que un lote
                # de cinco registros tuvo cuatro aceptados y un rechazado, y
                # nadie sabría qué pasó con el quinto.
                rechazos.extend(
                    Rechazo(tipo='valor', id=f'{evento.id}/{valor.campo}',
                            motivo='Su evento no entró.')
                    for valor in evento.valores)

        for entrada in lote.auditoria:
            aceptados += _guardar(con, rechazos, 'auditoria', entrada.id,
                                  lambda: _auditoria(con, entrada, lote, quien))

        registros = _cuantos(lote)
        bd.ejecutar(
            con,
            """
            INSERT INTO lote_sincronizacion (id, dispositivo_id, registros,
                                             aceptados, rechazados, detalle)
                 VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (id) DO NOTHING
            """,
            (lote.id, lote.dispositivo_id, registros, aceptados,
             len(rechazos), Jsonb([r.model_dump() for r in rechazos])),
        )

    return ResultadoLote(
        lote_id=lote.id,
        registros=registros,
        aceptados=aceptados,
        rechazados=len(rechazos),
        detalle=rechazos,
    )


def _cuantos(lote: Lote) -> int:
    return (len(lote.pacientes) + len(lote.consentimientos)
            + len(lote.eventos) + len(lote.auditoria)
            + sum(len(e.valores) for e in lote.eventos))


def _guardar(con, rechazos: list[Rechazo], tipo: str, ident,
             hacer) -> int:
    """Ejecuta un guardado en su propio punto de guardado.

    Sin esto, el primer error dejaría la transacción abortada y el resto del
    lote se perdería aunque estuviera bien.
    """
    try:
        with con.transaction():
            hacer()
        return 1
    except (psycopg.Error, Rechazado) as error:
        rechazos.append(Rechazo(tipo=tipo, id=str(ident),
                                motivo=_motivo(error)))
        return 0


def _motivo(error: Exception) -> str:
    """El mensaje de PostgreSQL, que es el que dice qué pasó de verdad.

    Va al diario del lote y vuelve al dispositivo: cuando alguien pregunte por
    qué un paciente no aparece en el servidor, la respuesta tiene que estar
    escrita en alguna parte.
    """
    if isinstance(error, Rechazado):
        return str(error)
    mensaje = error.diag.message_primary
    detalle = error.diag.message_detail
    if mensaje and detalle:
        return f'{mensaje} — {detalle}'
    return mensaje or str(error).strip()


# ── Guardado de cada tipo de registro ─────────────────────────────


def _paciente(con, paciente: PacienteEntrante, lote: Lote,
              quien: dict[str, Any]) -> None:
    """Ficha, identidad y asignación: los tres van juntos o no va ninguno.

    Un paciente sin su asignación sería un enrolamiento sin rama, y uno sin
    identidad sería un código que nadie puede relacionar con nadie en la sala.
    Como el punto de guardado envuelve los tres, o entran los tres o no entra
    ninguno.
    """
    _exigir_cei(con, paciente.institucion_codigo)

    hecho = bd.uno(
        con,
        """
        INSERT INTO paciente (id, codigo, institucion_codigo, edad, sexo,
                              enrolado_por, dispositivo_id, enrolado_en)
             VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (id) DO NOTHING
          RETURNING id
        """,
        (paciente.id, paciente.codigo, paciente.institucion_codigo,
         paciente.edad, paciente.sexo, quien['investigador_id'],
         lote.dispositivo_id, paciente.enrolado_en),
    )
    if hecho is None:
        # Ya estaba: el lote se reenvió, o el dispositivo lo reagrupó. La ficha
        # no se actualiza desde aquí — una corrección de la identidad pasa por
        # auditoría (CLAUDE.md §3), no por reenviar el paciente.
        return

    bd.ejecutar(
        con,
        """
        INSERT INTO identidad (paciente_id, nombre, numero_historia_clinica,
                               telefono_principal, telefono_secundario)
             VALUES (%s, %s, %s, %s, %s)
        """,
        (paciente.id, paciente.identidad.nombre,
         paciente.identidad.numero_historia_clinica,
         paciente.identidad.telefono_principal,
         paciente.identidad.telefono_secundario),
    )

    asignacion = paciente.asignacion
    bd.ejecutar(
        con,
        """
        INSERT INTO asignacion (secuencia_etiqueta, posicion, protocolo,
                                paciente_id, dispositivo_id, asignado_en)
             VALUES (%s, %s, %s, %s, %s, %s)
        """,
        (asignacion.secuencia_etiqueta, asignacion.posicion,
         asignacion.protocolo, paciente.id, lote.dispositivo_id,
         asignacion.asignado_en),
    )


def _exigir_cei(con, institucion_codigo: str) -> None:
    """Restricción CLAUDE.md §13: sin aprobación del CEI de ese centro, no.

    La app ya lo sabe —lo recibe en la configuración del estudio— pero esto es
    la última línea. Un dispositivo con una configuración vieja, o una versión
    de la app anterior a la comprobación, no debe poder meter pacientes reales
    en un centro que todavía no tiene permiso para reclutarlos.

    Se rechaza el registro, no el lote: el dispositivo lo conserva en la cola y
    entra solo en cuanto el centro quede aprobado.
    """
    fila = bd.uno(con, 'SELECT cei_aprobado FROM institucion WHERE codigo = %s',
                  (institucion_codigo,))
    if fila is None:
        raise Rechazado(
            f'El centro {institucion_codigo} no existe en el estudio.')
    if not fila['cei_aprobado']:
        raise Rechazado(
            f'El centro {institucion_codigo} no tiene aprobación del Comité de '
            'Ética registrada: no se admiten pacientes de ahí.')


def _consentimiento(con, consentimiento: ConsentimientoEntrante) -> None:
    bd.ejecutar(
        con,
        """
        INSERT INTO consentimiento (id, paciente_id, version_documento,
                                    codigo_cei, firmado_en, testigo_id, firma)
             VALUES (%s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (id) DO NOTHING
        """,
        (consentimiento.id, consentimiento.paciente_id,
         consentimiento.version_documento, consentimiento.codigo_cei,
         consentimiento.firmado_en, consentimiento.testigo_id,
         Jsonb(consentimiento.firma)),
    )


def _evento(con, evento: EventoEntrante, lote: Lote,
            quien: dict[str, Any]) -> None:
    """Solo llegan aquí los eventos **registrados**.

    Los borradores se quedan en el dispositivo: sincronizar datos a medio
    teclear llenaría la base central de registros que nadie sabría si son
    definitivos. Quien filtra es el cliente; el servidor no puede distinguirlos,
    y por eso conviene que quede escrito en los dos sitios.
    """
    bd.ejecutar(
        con,
        """
        INSERT INTO evento (id, paciente_id, tipo, ocurrencia,
                            fecha_ocurrencia, institucion_codigo,
                            recolector_id, dispositivo_id, fecha_captura)
             VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (id) DO NOTHING
        """,
        (evento.id, evento.paciente_id, evento.tipo, evento.ocurrencia,
         evento.fecha_ocurrencia, evento.institucion_codigo,
         quien['investigador_id'], lote.dispositivo_id, evento.fecha_captura),
    )


def _valor(con, evento: EventoEntrante, valor, quien: dict[str, Any]) -> None:
    """Inserta una versión nueva del campo, si el valor cambió.

    Si el valor que llega es el que ya está vigente, no se hace nada: un lote
    reenviado no debe dejar una fila nueva por cada campo, o el historial se
    llenaría de versiones idénticas que no corrigen nada.
    """
    vigente = bd.uno(
        con,
        'SELECT version, valor, tipo FROM evento_valor_vigente'
        ' WHERE evento_id = %s AND campo = %s',
        (evento.id, valor.campo))

    if vigente and vigente['valor'] == valor.valor and vigente['tipo'] == valor.tipo:
        return

    bd.ejecutar(
        con,
        """
        INSERT INTO evento_valor (evento_id, campo, version, tipo, valor,
                                  capturado_en, autor_id)
             VALUES (%s, %s, %s, %s, %s, %s, %s)
        """,
        (evento.id, valor.campo, (vigente['version'] + 1) if vigente else 1,
         valor.tipo, valor.valor, valor.capturado_en or evento.fecha_captura,
         quien['investigador_id']),
    )


def _auditoria(con, entrada: AuditoriaEntrante, lote: Lote,
               quien: dict[str, Any]) -> None:
    """La tabla no admite UPDATE ni DELETE, así que aquí solo cabe insertar.

    `ON CONFLICT DO NOTHING` y no `DO UPDATE`: lo segundo dispararía el
    disparador que rechaza modificaciones, que es exactamente lo que debe pasar.
    """
    bd.ejecutar(
        con,
        """
        INSERT INTO auditoria (id, ocurrido_en, autor_id, entidad, entidad_id,
                               descripcion_objetivo, campo, valor_anterior,
                               valor_nuevo, motivo, dispositivo_id)
             VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (id) DO NOTHING
        """,
        (entrada.id, entrada.ocurrido_en, quien['investigador_id'],
         entrada.entidad, entrada.entidad_id, entrada.descripcion_objetivo,
         entrada.campo, entrada.valor_anterior, entrada.valor_nuevo,
         entrada.motivo, lote.dispositivo_id),
    )

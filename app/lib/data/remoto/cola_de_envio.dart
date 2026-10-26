import 'dart:convert';

import '../../domain/models/audit_entry.dart';
import '../../domain/models/consent.dart';
import '../../domain/models/estudio_form_definition.dart';
import '../../domain/models/evento_clinico.dart';
import '../../domain/repositories/study_repository.dart';
import 'cliente_api.dart';
import 'cliente_remoto.dart';
import 'lote.dart';

/// Lo que el dispositivo tiene guardado, camino del servidor.
///
/// **Nada de esto es requisito para trabajar** (CLAUDE.md §12). La app captura
/// sin conexión y esta clase se limita a consolidar cuando la hay. Si nunca se
/// ejecuta, no se pierde nada: se acumula.
///
/// Tres reglas la gobiernan:
///
/// **Un envío se da por bueno registro a registro, no en bloque.** El servidor
/// contesta qué entró y qué no, y solo lo que entró se marca como enviado. Lo
/// rechazado se queda en la cola con su motivo escrito, para que alguien pueda
/// mirarlo — que es lo contrario de descartarlo en silencio.
///
/// **No llegar no es lo mismo que que te digan que no.** Sin conexión no se
/// toca nada y se reintenta luego. Con un rechazo del servidor, reintentar sin
/// más repetiría el error.
///
/// **Un lote se puede reenviar.** Su identificador lo genera el dispositivo, y
/// el servidor devuelve el resultado que ya tenía guardado. Es lo que hace
/// recuperable el caso que va a ocurrir de verdad: que el servidor guarde y la
/// respuesta se pierda por el camino.
class ColaDeEnvio {
  static const claveLoteEnVuelo = 'lote_en_vuelo';
  ColaDeEnvio({
    required this.repo,
    required this.api,
    required this.dispositivoId,
    this.maxPacientesPorLote,
  });

  final StudyRepository repo;
  final ClienteRemoto api;
  final String dispositivoId;
  final int? maxPacientesPorLote;

  /// Cuántos registros esperan a ser enviados.
  int get pendientes => repo.pendienteDeEnvio().registros;

  /// Envía lo pendiente y devuelve cómo fue.
  ///
  /// Un solo lote por llamada. Con la conectividad del equipo, un envío grande
  /// que se corta a la mitad y hay que repetir entero es peor que varios
  /// pequeños; quien llame puede repetir mientras queden pendientes.
  Future<EnvioRealizado> sincronizar() async {
    final pendiente = repo.pendienteDeEnvio();
    if (pendiente.vacio) {
      repo.guardarAjuste(claveLoteEnVuelo, '');
      return const EnvioRealizado.nadaQueEnviar();
    }

    try {
      final lote = _lotePersistente(pendiente);
      final resultado = await api.enviar(lote);
      if (resultado.loteId != lote.id) {
        throw const ErrorDelServidor(
            200, 'El servidor acusó un lote distinto del enviado.');
      }
      _anotar(lote, resultado);
      repo.guardarAjuste(claveLoteEnVuelo, '');
      return EnvioRealizado.hecho(resultado);
    } on SinConexion catch (error) {
      // No se llegó: la cola se queda intacta y se reintenta más tarde.
      return EnvioRealizado.sinConexion(error);
    } on SesionCaducada catch (error) {
      return EnvioRealizado.sesionCaducada(error);
    } on ErrorDelServidor catch (error) {
      // Se llegó y dijo que no al lote entero — normalmente porque la app
      // envió algo con una forma que el servidor no sabe leer. Eso no se
      // arregla reintentando.
      return EnvioRealizado.rechazado(error);
    } on StateError catch (error) {
      return EnvioRealizado.rechazado(ErrorDelServidor(409, error.message));
    }
  }

  Lote _lotePersistente(Pendiente pendiente) {
    final guardado = repo.ajuste(claveLoteEnVuelo);
    if (guardado != null && guardado.isNotEmpty) {
      final datos = jsonDecode(guardado) as Map<String, dynamic>;
      final ids = (datos['ids'] as List).cast<String>().toSet();
      final seleccion = Pendiente(
        pacientes:
            pendiente.pacientes.where((p) => ids.contains(p.id)).toList(),
        consentimientos:
            pendiente.consentimientos.where((c) => ids.contains(c.id)).toList(),
        eventos: pendiente.eventos.where((e) => ids.contains(e.id)).toList(),
        auditoria:
            pendiente.auditoria.where((a) => ids.contains(a.id)).toList(),
      );
      if (seleccion.registros != ids.length) {
        throw StateError('El lote pendiente cambió antes de recibir su acuse.');
      }
      final lote =
          _armar(seleccion, id: datos['id'] as String, limitado: false);
      if (jsonEncode(lote.aJson()) != datos['contenido']) {
        throw StateError(
            'Un registro del lote cambió antes de recibir su acuse. '
            'Requiere revisión para no perder la corrección.');
      }
      return lote;
    }
    final lote = _armar(pendiente);
    repo.guardarAjuste(
        claveLoteEnVuelo,
        jsonEncode({
          'id': lote.id,
          'contenido': jsonEncode(lote.aJson()),
          'ids': [
            for (final p in lote.pacientes) p.paciente.id,
            for (final c in lote.consentimientos) c.consentimiento.id,
            for (final e in lote.eventos) e.evento.id,
            for (final a in lote.auditoria) a.entrada.id,
          ],
        }));
    return lote;
  }

  Lote _armar(Pendiente pendiente, {String? id, bool limitado = true}) {
    limitado = limitado && maxPacientesPorLote != null;
    final soloPacientes = limitado && pendiente.pacientes.isNotEmpty;
    final pacientes = limitado
        ? pendiente.pacientes.take(maxPacientesPorLote!)
        : pendiente.pacientes;
    // Cada evento consulta paciente y consentimiento en las reglas. Ocho
    // dejan margen bajo el límite de 20 accesos por transacción de Firestore.
    var cupo = 8;
    final consentimientos = soloPacientes
        ? const <Consent>[]
        : pendiente.consentimientos
            .take(limitado ? cupo : pendiente.consentimientos.length)
            .toList();
    cupo -= consentimientos.length;
    final eventos = soloPacientes
        ? const <EventoClinico>[]
        : pendiente.eventos
            .take(limitado ? cupo : pendiente.eventos.length)
            .toList();
    cupo -= eventos.length;
    final auditoria = soloPacientes
        ? const <AuditEntry>[]
        : pendiente.auditoria
            .take(limitado ? cupo : pendiente.auditoria.length)
            .toList();
    return Lote(
      id: id,
      dispositivoId: dispositivoId,
      pacientes: [
        for (final p in pacientes) PacienteEnviable(p),
      ],
      consentimientos: [
        for (final c in consentimientos) ConsentimientoEnviable(c),
      ],
      eventos: [
        for (final e in eventos)
          EventoEnviable(e, _tipos(e),
              consentimientoId: repo.paciente(e.patientId)?.consentimientoId),
      ],
      auditoria: [
        for (final a in auditoria) AuditoriaEnviable(a),
      ],
    );
  }

  /// El tipo de dato de cada campo, sacado de la definición del formulario.
  ///
  /// El servidor lo necesita declarado y no lo adivina: un «30» puede ser un
  /// número o el texto de una opción, y en el dataset exportado esa diferencia
  /// importa.
  Map<String, String> _tipos(EventoClinico evento) {
    final definicion = repo.config.definicionFormulario.para(evento.tipo);
    if (definicion == null) return const {};
    return {
      for (final campo in definicion.campos)
        campo.key: _nombreDelTipo(campo.tipo),
    };
  }

  /// Marca como enviado lo que el servidor aceptó, y solo eso.
  void _anotar(Lote lote, ResultadoLote resultado) {
    final rechazados = resultado.idsRechazados;
    final aceptados = [
      for (final p in lote.pacientes)
        if (!rechazados.contains(p.paciente.id)) p.paciente.id,
      for (final c in lote.consentimientos)
        if (!rechazados.contains(c.consentimiento.id)) c.consentimiento.id,
      for (final e in lote.eventos)
        if (!rechazados.contains(e.evento.id)) e.evento.id,
      for (final a in lote.auditoria)
        if (!rechazados.contains(a.entrada.id)) a.entrada.id,
    ];
    repo.anotarEnviados(loteId: lote.id, ids: aceptados);
  }

  /// Los nombres que entiende el servidor, que son los del enum de la base.
  static String _nombreDelTipo(FieldType tipo) => switch (tipo) {
        FieldType.numero => 'numero',
        FieldType.fecha => 'fecha',
        FieldType.siNo => 'booleano',
        FieldType.seleccionUnica || FieldType.seleccionMultiple => 'lista',
        FieldType.texto || FieldType.textoLargo => 'texto',
      };
}

/// Cómo fue un envío. Cinco desenlaces, y cada uno pide algo distinto.
sealed class EnvioRealizado {
  const EnvioRealizado();

  const factory EnvioRealizado.nadaQueEnviar() = NadaQueEnviar;
  const factory EnvioRealizado.hecho(ResultadoLote resultado) = Hecho;
  const factory EnvioRealizado.sinConexion(SinConexion error) = SinRed;
  const factory EnvioRealizado.sesionCaducada(SesionCaducada error) =
      SesionPerdida;
  const factory EnvioRealizado.rechazado(ErrorDelServidor error) = Rechazado;

  /// Si conviene volver a intentarlo con lo mismo.
  bool get seReintenta => this is SinRed;

  /// Qué se le dice a quien está mirando el teléfono.
  String get mensaje => switch (this) {
        NadaQueEnviar() => 'No hay nada pendiente de enviar.',
        Hecho(:final resultado) when resultado.todoEntro =>
          'Enviados ${resultado.aceptados} registros.',
        Hecho(:final resultado) =>
          'Enviados ${resultado.aceptados}; ${resultado.rechazados} '
              'quedaron sin entrar.',
        SinRed() => 'Sin conexión. Lo pendiente sigue guardado en el aparato.',
        SesionPerdida() => 'La sesión con el servidor caducó. Vuelva a entrar.',
        Rechazado(:final error) => 'El servidor no admitió el envío: '
            '${error.detalle}',
      };
}

class NadaQueEnviar extends EnvioRealizado {
  const NadaQueEnviar();
}

class Hecho extends EnvioRealizado {
  const Hecho(this.resultado);
  final ResultadoLote resultado;
}

class SinRed extends EnvioRealizado {
  const SinRed(this.error);
  final SinConexion error;
}

class SesionPerdida extends EnvioRealizado {
  const SesionPerdida(this.error);
  final SesionCaducada error;
}

class Rechazado extends EnvioRealizado {
  const Rechazado(this.error);
  final ErrorDelServidor error;
}

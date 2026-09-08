import '../data/local/anexo4.dart';
import 'models/evento_clinico.dart';
import 'models/patient.dart';
import 'models/role.dart';
import 'repositories/study_repository.dart';

/// Lo que el estudio está esperando de alguien.
///
/// **No hay calendario guardado en ninguna parte** (CLAUDE.md §4). Una alerta
/// no es una fila que se crea al enrolar y se marca como cumplida: se deduce
/// cada vez, mirando qué eventos existen y cuáles el protocolo espera a
/// continuación. Un calendario pre-creado obligaría a saber de antemano lo que
/// va a pasar, y en un ensayo dirigido por eventos no se sabe.
///
/// La consecuencia práctica es que una alerta desaparece sola en cuanto se
/// registra el evento que la cierra, sin que nadie tenga que acordarse de
/// tacharla. Y que un paciente que muere deja de generar avisos de seguimiento
/// sin ninguna cancelación explícita: los siguientes contactos ya no proceden.
class Alertas {
  const Alertas._();

  /// Lo pendiente hoy, ordenado por cuánto lleva esperando.
  ///
  /// Con [para], solo lo que esa persona puede resolver: las alertas de quien
  /// no captura ese hito no son suyas, y una lista con avisos que uno no puede
  /// atender se aprende a ignorar.
  static List<Alerta> pendientes(
    StudyRepository repo, {
    required DateTime hoy,
    Investigador? para,
  }) {
    final lista = <Alerta>[];
    for (final paciente in repo.pacientes()) {
      final eventos = repo.eventosDe(paciente.id)
          .where((e) => e.estado == EstadoEvento.registrado)
          .toList();
      lista
        ..addAll(_listoParaEvaluar(paciente, eventos))
        ..addAll(_contactosDeSeguimiento(paciente, eventos, hoy));
    }

    final visibles = para == null
        ? lista
        : lista.where((a) => para.puedeCapturar(a.eventoQueLaCierra)).toList();
    visibles.sort((a, b) => a.desde.compareTo(b.desde));
    return visibles;
  }

  /// El paciente se extubó y nadie ha registrado sus desenlaces.
  ///
  /// Es la segunda pregunta del Anexo 4: avisar al evaluador el mismo día de la
  /// extubación. Aquí el aviso no se manda, se calcula — así también aparece si
  /// el evaluador no abrió la app ese día, que es cuando de verdad hace falta.
  static Iterable<Alerta> _listoParaEvaluar(
      Patient paciente, List<EventoClinico> eventos) sync* {
    final extubacion = _ultimo(eventos, TipoEvento.extubacion);
    if (extubacion == null) return;

    // Un paciente traqueostomizado no se extubó: su trayectoria se desvió y no
    // hay desenlace de extubación que evaluar todavía.
    if (extubacion.valores['traqueostomia'] == true) return;

    if (_ultimo(eventos, TipoEvento.desenlaces) != null) return;

    yield Alerta(
      tipo: TipoAlerta.listoParaEvaluar,
      paciente: paciente,
      detalle: 'Extubado el ${_fecha(extubacion.fechaOcurrencia)}',
      desde: extubacion.fechaOcurrencia,
      eventoQueLaCierra: TipoEvento.desenlaces,
    );
  }

  /// Toca contactar al paciente a los 7, 14 o 28 días del egreso.
  ///
  /// Es la primera pregunta del Anexo 4. Los días salen de
  /// [Anexo4.ventanasSeguimiento] y no están escritos aquí: si el protocolo
  /// cambia las ventanas, cambian en un sitio.
  static Iterable<Alerta> _contactosDeSeguimiento(
      Patient paciente, List<EventoClinico> eventos, DateTime hoy) sync* {
    final desenlaces = _ultimo(eventos, TipoEvento.desenlaces);
    if (desenlaces == null) return;
    if (desenlaces.valores['estado_egreso'] != 'Vivo') return;

    final egreso = _comoFecha(desenlaces.valores['fecha_egreso_uci']);
    if (egreso == null) return;

    final contactos =
        eventos.where((e) => e.tipo == TipoEvento.seguimientoPostEgreso);

    // Si ya se registró un fallecimiento, el seguimiento terminó. No hace falta
    // cancelar nada: deja de haber contactos que pedir.
    if (contactos.any((e) => e.valores['fallecido'] == true)) return;

    final hechas = contactos.map((e) => e.valores['ventana_contacto']).toSet();

    for (final dias in Anexo4.ventanasSeguimiento) {
      final etiqueta = Anexo4.ventana(dias);
      if (hechas.contains(etiqueta)) continue;

      final vence = egreso.add(Duration(days: dias));
      if (vence.isAfter(hoy)) continue;

      yield Alerta(
        tipo: TipoAlerta.contactoSeguimiento,
        paciente: paciente,
        detalle: etiqueta,
        desde: vence,
        eventoQueLaCierra: TipoEvento.seguimientoPostEgreso,
      );
    }
  }

  static EventoClinico? _ultimo(List<EventoClinico> eventos, TipoEvento tipo) {
    EventoClinico? encontrado;
    for (final e in eventos) {
      if (e.tipo != tipo) continue;
      if (encontrado == null || e.ocurrencia > encontrado.ocurrencia) {
        encontrado = e;
      }
    }
    return encontrado;
  }

  /// Las fechas de los formularios se guardan como `2026-09-14`.
  static DateTime? _comoFecha(Object? valor) => switch (valor) {
        DateTime d => DateTime(d.year, d.month, d.day),
        String s => DateTime.tryParse(s),
        _ => null,
      };

  static String _fecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}';
}

enum TipoAlerta {
  /// Toca llamar al paciente egresado.
  contactoSeguimiento('Contacto de seguimiento'),

  /// Hay un paciente extubado sin desenlaces registrados.
  listoParaEvaluar('Listo para evaluar desenlaces');

  const TipoAlerta(this.etiqueta);
  final String etiqueta;
}

class Alerta {
  const Alerta({
    required this.tipo,
    required this.paciente,
    required this.detalle,
    required this.desde,
    required this.eventoQueLaCierra,
  });

  final TipoAlerta tipo;
  final Patient paciente;

  /// Qué se espera exactamente: «Día 14 tras el egreso», «Extubado el 03/09».
  final String detalle;

  /// Desde cuándo procede. Ordena la lista: lo que lleva más tiempo esperando
  /// va arriba.
  final DateTime desde;

  /// El hito cuyo registro hace desaparecer la alerta.
  final TipoEvento eventoQueLaCierra;

  int diasEsperando(DateTime hoy) => hoy.difference(desde).inDays;

  /// Los contactos de seguimiento tienen ventana: pasados unos días, la
  /// respuesta ya no cae donde el protocolo la pedía. No bloquea nada —el dato
  /// tardío sigue valiendo más que ninguno— pero conviene que se note.
  bool venceHoy(DateTime hoy) => diasEsperando(hoy) >= 3;
}

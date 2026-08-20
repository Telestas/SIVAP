import 'protocolo.dart';

/// Ficha de identidad del paciente.
///
/// Restricción no negociable (CLAUDE.md §1): la identidad vive separada de los
/// datos clínicos. Esta clase NO contiene ni un solo dato de visita; el vínculo
/// es [id] y nada más. Eso permite exportar el dataset clínico sin identidad.
class Patient {
  const Patient({
    required this.id,
    required this.nombre,
    required this.carneIdentidad,
    required this.edad,
    required this.sexo,
    required this.numeroHistoriaClinica,
    required this.telefono,
    required this.direccion,
    required this.protocolo,
    required this.bloqueAleatorizacion,
    required this.asignadoEn,
    required this.recolectorId,
    required this.enroladoEn,
    this.consentimientoId,
  });

  final String id;
  final String nombre;
  final String carneIdentidad;
  final int edad;
  final Sexo sexo;
  final String numeroHistoriaClinica;
  final String telefono;
  final String direccion;

  /// Asignada por el módulo de aleatorización, nunca elegida por el investigador.
  final Protocolo protocolo;
  final String bloqueAleatorizacion;
  final DateTime asignadoEn;

  final String recolectorId;
  final DateTime enroladoEn;

  /// Null mientras no se registre el consentimiento informado. Sin esto no se
  /// pueden capturar visitas (CLAUDE.md §8).
  final String? consentimientoId;

  bool get tieneConsentimiento => consentimientoId != null;

  /// "62 a · M" — la línea demográfica que usa el diseño en tarjetas y tablas.
  String get demografia => '$edad a · ${sexo.abreviatura}';

  /// "Estévez Cruz" — apellidos, para referirse al paciente en el historial de
  /// auditoría sin repetir el nombre completo en cada fila.
  String get apellidos {
    final partes = nombre.split(' ');
    return partes.length <= 2 ? nombre : partes.sublist(1).join(' ');
  }

  Patient copyWith({String? consentimientoId, String? telefono, String? direccion}) =>
      Patient(
        id: id,
        nombre: nombre,
        carneIdentidad: carneIdentidad,
        edad: edad,
        sexo: sexo,
        numeroHistoriaClinica: numeroHistoriaClinica,
        telefono: telefono ?? this.telefono,
        direccion: direccion ?? this.direccion,
        protocolo: protocolo,
        bloqueAleatorizacion: bloqueAleatorizacion,
        asignadoEn: asignadoEn,
        recolectorId: recolectorId,
        enroladoEn: enroladoEn,
        consentimientoId: consentimientoId ?? this.consentimientoId,
      );
}

enum Sexo {
  masculino('M'),
  femenino('F');

  const Sexo(this.abreviatura);
  final String abreviatura;
}

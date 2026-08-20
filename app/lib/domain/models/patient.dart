import 'institucion.dart';
import 'protocolo.dart';

/// Ficha del paciente.
///
/// **Restricción no negociable (CLAUDE.md §1).** La identidad vive separada de
/// los datos clínicos. Esta clase NO contiene ni un solo dato de evento; el
/// vínculo es [id] y nada más. Eso permite exportar el dataset clínico sin
/// identidad.
///
/// **Y §9, minimización.** Solo se guarda lo que el formulario del estudio
/// exige. El carné de identidad y la dirección se retiraron: el Anexo 4 no los
/// pide, y cada dato personal almacenado es superficie de riesgo que hay que
/// justificar ante el Comité de Ética.
///
/// [nombre] y [numeroHistoriaClinica] **tampoco los pide el Anexo 4** y se
/// conservan por decisión explícita: el equipo necesita identificar al paciente
/// en la sala. Viven solo en la ficha y nunca salen en el dataset clínico. Es
/// una excepción a justificar ante el CEI, no un descuido — ver
/// `docs/PENDIENTE.md`.
class Patient {
  const Patient({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.numeroHistoriaClinica,
    required this.telefonoPrincipal,
    required this.institucion,
    required this.edad,
    required this.sexo,
    required this.protocolo,
    required this.secuencia,
    required this.posicionSecuencia,
    required this.asignadoEn,
    required this.recolectorId,
    required this.enroladoEn,
    this.telefonoSecundario,
    this.consentimientoId,
  });

  /// Identificador interno, aleatorio de 128 bits. Es la clave real y nunca
  /// choca entre dispositivos, aunque se cree sin conexión.
  final String id;

  /// Código del estudio: prefijo del centro más correlativo, «HC-004».
  /// Es lo que se ve en pantalla y lo que sale en el dataset exportado.
  ///
  /// Cuidado: los correlativos generados sin conexión en dos dispositivos del
  /// mismo centro pueden repetirse hasta que sincronicen. Es molesto pero no
  /// corrompe nada, porque la clave real es [id].
  final String codigo;

  final String nombre;
  final String numeroHistoriaClinica;
  final String telefonoPrincipal;
  final String? telefonoSecundario;

  /// Centro donde se enroló (CLAUDE.md §8).
  final Institucion institucion;

  // Variables del Módulo 1 que además se usan para leer la ficha en pantalla.
  final int edad;
  final Sexo sexo;

  /// Asignado por el módulo de aleatorización, nunca elegido por nadie.
  final Protocolo protocolo;

  /// Etiqueta de la secuencia de la que salió la asignación, y la posición que
  /// ocupó. Con la semilla del expediente, permiten recalcular esta asignación
  /// concreta desde cero.
  final String secuencia;
  final int posicionSecuencia;
  final DateTime asignadoEn;

  final String recolectorId;
  final DateTime enroladoEn;

  /// Null mientras no se registre el consentimiento informado. Sin esto no se
  /// pueden capturar eventos clínicos (CLAUDE.md §13).
  final String? consentimientoId;

  bool get tieneConsentimiento => consentimientoId != null;

  /// "62 a · M" — la línea demográfica de tarjetas y tablas.
  String get demografia => '$edad a · ${sexo.abreviatura}';

  /// "Estévez Cruz" — apellidos, para referirse al paciente en el historial de
  /// auditoría sin repetir el nombre completo en cada fila.
  String get apellidos {
    final partes = nombre.split(' ');
    return partes.length <= 2 ? nombre : partes.sublist(1).join(' ');
  }

  Patient copyWith({
    String? consentimientoId,
    String? telefonoPrincipal,
    String? telefonoSecundario,
  }) =>
      Patient(
        id: id,
        codigo: codigo,
        nombre: nombre,
        numeroHistoriaClinica: numeroHistoriaClinica,
        telefonoPrincipal: telefonoPrincipal ?? this.telefonoPrincipal,
        telefonoSecundario: telefonoSecundario ?? this.telefonoSecundario,
        institucion: institucion,
        edad: edad,
        sexo: sexo,
        protocolo: protocolo,
        secuencia: secuencia,
        posicionSecuencia: posicionSecuencia,
        asignadoEn: asignadoEn,
        recolectorId: recolectorId,
        enroladoEn: enroladoEn,
        consentimientoId: consentimientoId ?? this.consentimientoId,
      );
}

enum Sexo {
  masculino('M', 'Masculino'),
  femenino('F', 'Femenino');

  const Sexo(this.abreviatura, this.etiqueta);
  final String abreviatura;
  final String etiqueta;
}

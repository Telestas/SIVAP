/// Consentimiento informado firmado por un paciente.
///
/// Guarda la versión exacta del documento aprobado por el CEI, para que años
/// después se sepa qué texto firmó cada paciente.
class Consent {
  const Consent({
    required this.id,
    required this.patientId,
    required this.versionDocumento,
    required this.codigoCei,
    required this.firmadoEn,
    required this.testigoId,
    required this.firmaTrazos,
  });

  final String id;
  final String patientId;
  final String versionDocumento;
  final String codigoCei;
  final DateTime firmadoEn;
  final String testigoId;

  /// Trazos normalizados de la firma (0..1 en ambos ejes), independientes del
  /// tamaño de pantalla del dispositivo que capturó.
  final List<List<({double x, double y})>> firmaTrazos;
}

/// Texto del modelo de consentimiento aprobado. Es dato, no código: se
/// versiona y se sustituye sin recompilar cuando el CEI apruebe una revisión.
class ConsentDocument {
  const ConsentDocument({
    required this.version,
    required this.codigoCei,
    required this.vigenteDesde,
    required this.parrafos,
    required this.declaraciones,
  });

  final String version;
  final String codigoCei;
  final String vigenteDesde;
  final List<String> parrafos;

  /// Casillas que el paciente marca una a una antes de firmar.
  final List<String> declaraciones;
}

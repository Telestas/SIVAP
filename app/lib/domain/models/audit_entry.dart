/// Entrada del registro de auditoría.
///
/// Restricción no negociable (CLAUDE.md §2): ningún registro ya enviado se
/// sobrescribe en silencio. Toda corrección produce una de estas — incluida la
/// que hace el administrador. [motivo] es obligatorio: sin motivo no hay
/// corrección, y la capa de datos lo exige, no la pantalla.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.ocurridoEn,
    required this.autorId,
    required this.autorNombre,
    required this.entidad,
    required this.entidadId,
    required this.descripcionObjetivo,
    required this.campo,
    required this.valorAnterior,
    required this.valorNuevo,
    required this.motivo,
  });

  final String id;
  final DateTime ocurridoEn;
  final String autorId;
  final String autorNombre;

  final AuditEntity entidad;
  final String entidadId;

  /// Referencia legible del objetivo: "Estévez Cruz · D3", "Sáez Roque · ficha".
  final String descripcionObjetivo;

  final String campo;
  final String? valorAnterior;
  final String? valorNuevo;
  final String motivo;
}

enum AuditEntity { ficha, visita, consentimiento, usuario }

/// Roles del estudio.
///
/// PROVISIONAL: estos son los tres roles del modelo anterior. El diseño de
/// LIVERE exige cuatro funciones separadas por razones metodológicas —
/// reclutador, aplicador, evaluador de desenlaces e investigador principal—,
/// porque quien selecciona pacientes debe estar cegado a la secuencia y quien
/// evalúa desenlaces, cegado a la rama (BASES §4).
///
/// Sustituirlos es el paso 6 de `docs/REENCAMINAMIENTO.md`. La forma es la
/// correcta —permisos como propiedades del enum—, lo que cambia es el
/// contenido.
enum Role {
  observador('Observador', 'Consulta toda la cohorte en solo lectura.'),
  recolector('Recolector de campo',
      'Enrola pacientes y captura eventos clínicos. No edita lo ya registrado.'),
  administrador('Administrador', 'Control total. Toda corrección queda en auditoría.');

  const Role(this.label, this.description);
  final String label;
  final String description;

  bool get puedeEnrolar => this == recolector || this == administrador;
  bool get puedeCapturarEventos => this == recolector || this == administrador;
  bool get puedeGestionarUsuarios => this == administrador;
  bool get puedeExportar => this == administrador;

  /// Solo el administrador corrige un registro ya enviado, y nunca en silencio:
  /// la corrección exige una entrada de auditoría con motivo.
  bool get puedeCorregirEnviado => this == administrador;

  /// El recolector solo ve su propia carga; los demás ven la cohorte completa.
  bool get veCohorteCompleta => this != recolector;
}

class Investigador {
  const Investigador({
    required this.id,
    required this.usuario,
    required this.nombre,
    required this.role,
  });

  final String id;
  final String usuario;
  final String nombre;
  final Role role;

  /// Iniciales para el avatar del encabezado ("Dra. C. Morales" → "CM").
  String get iniciales {
    final partes = nombre
        .split(RegExp(r'[\s.]+'))
        .where((p) => p.isNotEmpty && p[0] == p[0].toUpperCase())
        .where((p) => !const {'Dr', 'Dra'}.contains(p))
        .toList();
    if (partes.isEmpty) return usuario.substring(0, 2).toUpperCase();
    if (partes.length == 1) return partes.first.substring(0, 2).toUpperCase();
    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }
}

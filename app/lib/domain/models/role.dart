/// Roles del estudio. La tabla de permisos vive en `BASES_MVP_SIVAP.md` §4;
/// aquí se codifica para que ninguna pantalla la interprete a su manera.
enum Role {
  observador('Observador', 'Consulta toda la cohorte en solo lectura.'),
  recolector('Recolector de campo',
      'Crea pacientes y visitas propias. No edita registros ya enviados.'),
  administrador('Administrador', 'Control total. Toda corrección queda en auditoría.');

  const Role(this.label, this.description);
  final String label;
  final String description;

  bool get puedeEnrolar => this == recolector || this == administrador;
  bool get puedeCapturarVisitas => this == recolector || this == administrador;
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

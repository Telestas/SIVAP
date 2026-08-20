import 'evento_clinico.dart';
import 'institucion.dart';

/// Función que cumple un investigador dentro del ensayo.
///
/// **No son niveles de permiso: son la separación de funciones que exige el
/// diseño de LIVERE** (BASES §4). Quien selecciona pacientes debe estar cegado
/// a la secuencia de asignación; quien evalúa desenlaces, cegado a la rama que
/// recibió el paciente. Si una sola persona ve las dos cosas, el cegamiento se
/// pierde aunque el software funcione perfectamente.
///
/// Por eso los permisos de captura van por tipo de evento y no por «puede
/// escribir sí o no»: el aplicador captura las fases del protocolo, el
/// evaluador captura los desenlaces, y ninguno de los dos hace el trabajo del
/// otro.
enum Rol {
  reclutador(
    etiqueta: 'Reclutador',
    descripcion: 'Verifica elegibilidad, registra el consentimiento y enrola.',
    cegadoA: 'La secuencia y qué rama viene después.',
  ),
  aplicador(
    etiqueta: 'Aplicador',
    descripcion: 'Ejecuta el protocolo asignado y captura los eventos de fase.',
    cegadoA: 'Cuál rama corresponde a cada protocolo terapéutico.',
  ),
  evaluadorDesenlaces(
    etiqueta: 'Evaluador de desenlaces',
    descripcion: 'Registra reintubación, egreso, mortalidad y eventos adversos.',
    cegadoA: 'La rama asignada al paciente.',
  ),
  analista(
    etiqueta: 'Analista',
    descripcion: 'Consulta y exporta el dataset completo, sin identidad.',
    cegadoA: 'Qué protocolo terapéutico hay detrás de A y de B.',
  ),
  investigadorPrincipal(
    etiqueta: 'Investigador principal',
    descripcion: 'Administra el estudio, corrige con auditoría y gestiona usuarios.',
    cegadoA: 'Nadie. Aun así, el sistema no almacena la correspondencia A/B.',
  ),
  observador(
    etiqueta: 'Observador',
    descripcion: 'Consulta la cohorte completa en solo lectura.',
    cegadoA: 'Qué protocolo terapéutico hay detrás de A y de B.',
  );

  const Rol({
    required this.etiqueta,
    required this.descripcion,
    required this.cegadoA,
  });

  final String etiqueta;
  final String descripcion;

  /// A qué está cegada esta función. Se muestra en la pantalla de acceso: quien
  /// entra debe saber qué no va a ver, y por qué.
  final String cegadoA;

  bool get puedeEnrolar => this == reclutador || this == investigadorPrincipal;

  bool get puedeGestionarUsuarios => this == investigadorPrincipal;

  bool get puedeExportar => this == analista || this == investigadorPrincipal;

  /// Solo el investigador principal corrige un registro ya enviado, y nunca en
  /// silencio: la corrección exige motivo y genera auditoría (CLAUDE.md §3).
  bool get puedeCorregirRegistrado => this == investigadorPrincipal;

  /// El aplicador solo ve su propia carga; el resto ve la cohorte completa.
  bool get veCohorteCompleta => this != aplicador && this != reclutador;

  /// **El evaluador de desenlaces no ve la rama.** Es la parte del cegamiento
  /// que el software puede hacer valer de verdad: si supiera en qué rama está
  /// el paciente, su juicio sobre si hubo extubación fallida dejaría de ser
  /// independiente, y ese es el desenlace principal del ensayo.
  bool get veRamaAsignada => this != evaluadorDesenlaces;

  /// Qué hitos captura esta función.
  Set<TipoEvento> get eventosQueCaptura => switch (this) {
        reclutador => {TipoEvento.enrolamiento},
        aplicador => {
            TipoEvento.estratificacionRiesgo,
            TipoEvento.cribado,
            TipoEvento.evaluacionDiaria,
            TipoEvento.pruebaVentilacionEspontanea,
            TipoEvento.traqueostomia,
            TipoEvento.extubacion,
            TipoEvento.soportePostExtubacion,
          },
        evaluadorDesenlaces => {
            TipoEvento.reintubacion,
            TipoEvento.egresoUci,
            TipoEvento.seguimientoPostEgreso,
          },
        investigadorPrincipal => TipoEvento.values.toSet(),
        analista || observador => const {},
      };
}

/// Usuario del sistema.
///
/// Lleva un **conjunto** de funciones, no una sola, porque en equipos pequeños
/// es frecuente que un mismo médico cumpla varias. Si eso compromete el
/// cegamiento es una decisión de la investigadora principal, no del desarrollo:
/// por eso [StudyConfig.permiteAcumularRoles] la deja como configuración del
/// estudio y no como una regla escrita en el código.
///
/// La combinación peligrosa está identificada: **aplicador + evaluador de
/// desenlaces en la misma persona anula el cegamiento del desenlace principal**,
/// porque quien aplicó el protocolo sabe qué rama es y luego juzga si la
/// extubación falló.
class Investigador {
  const Investigador({
    required this.id,
    required this.usuario,
    required this.nombre,
    required this.roles,
    required this.institucion,
  });

  final String id;
  final String usuario;
  final String nombre;
  final Set<Rol> roles;

  /// Centro al que pertenece (CLAUDE.md §8).
  final Institucion institucion;

  /// Función principal, para mostrar cuando solo cabe una.
  Rol get rolPrincipal =>
      roles.reduce((a, b) => a.index < b.index ? a : b);

  String get etiquetaRoles => roles.map((r) => r.etiqueta).join(' · ');

  // ── Permisos agregados ──────────────────────────────────────────
  // Basta con que una de sus funciones lo permita.

  bool get puedeEnrolar => roles.any((r) => r.puedeEnrolar);
  bool get puedeGestionarUsuarios => roles.any((r) => r.puedeGestionarUsuarios);
  bool get puedeExportar => roles.any((r) => r.puedeExportar);
  bool get puedeCorregirRegistrado =>
      roles.any((r) => r.puedeCorregirRegistrado);
  bool get veCohorteCompleta => roles.any((r) => r.veCohorteCompleta);

  /// La rama se oculta si **alguna** de sus funciones exige cegamiento. Aquí la
  /// suma de permisos no aplica: en cegamiento, la restricción más estricta es
  /// la que manda. Un evaluador que además es aplicador seguirá sin ver la
  /// rama, aunque como aplicador podría.
  bool get veRamaAsignada => roles.every((r) => r.veRamaAsignada);

  bool get puedeCapturarEventos => roles.any((r) => r.eventosQueCaptura.isNotEmpty);

  bool puedeCapturar(TipoEvento tipo) =>
      roles.any((r) => r.eventosQueCaptura.contains(tipo));

  Set<TipoEvento> get eventosQueCaptura =>
      {for (final r in roles) ...r.eventosQueCaptura};

  /// Combinación que rompe el cegamiento del desenlace principal.
  bool get acumulaFuncionesIncompatibles =>
      roles.contains(Rol.aplicador) && roles.contains(Rol.evaluadorDesenlaces);

  /// Iniciales para el avatar del encabezado ("Dra. Morales" → "M").
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

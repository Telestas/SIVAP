import 'package:flutter/widgets.dart';

/// Tokens extraídos del canvas de diseño (`design/SIVAP.dc.html`).
///
/// Regla: ningún widget declara un color literal. Si un valor no está aquí,
/// se añade aquí primero — así un ajuste de identidad visual es un solo archivo.
class T {
  const T._();

  // ── Superficies ────────────────────────────────────────────────
  static const canvas = Color(0xFFECECEB);
  static const surface = Color(0xFFFBFBFA);
  static const card = Color(0xFFFFFFFF);
  static const subtle = Color(0xFFF4F5F6);

  // ── Texto ──────────────────────────────────────────────────────
  static const ink = Color(0xFF16181A);
  static const inkSoft = Color(0xFF2A2E33);
  static const body = Color(0xFF4A5158);
  static const secondary = Color(0xFF5F6771);
  static const muted = Color(0xFF7A828C);
  static const faint = Color(0xFF8B929A);
  static const ghost = Color(0xFF9AA1A8);
  static const disabled = Color(0xFFB9BEC4);
  static const onInk = Color(0xFFFBFBFA);

  // ── Bordes ─────────────────────────────────────────────────────
  static const line = Color(0xFFDCDFE3);
  static const lineSoft = Color(0xFFE0E2E5);
  static const lineFaint = Color(0xFFE4E6E8);
  static const lineHair = Color(0xFFEEF0F1);
  static const lineFrame = Color(0xFFD5D8DB);
  static const lineDashed = Color(0xFFC6CAD0);

  // ── Acento (teal institucional) ────────────────────────────────
  static const accent = Color(0xFF17615A);
  static const accentDark = Color(0xFF0F423D);
  static const accentTint = Color(0xFFE9F2F0);

  // ── Semántica de estado ────────────────────────────────────────
  /// Ámbar: pendiente, sin conexión, en cola, borrador.
  static const warnBg = Color(0xFFFDF1DA);
  static const warnLine = Color(0xFFEED9AC);
  static const warnFg = Color(0xFF7A5710);
  static const warnDot = Color(0xFFC98A1A);

  /// Verde: enviado, sincronizado, visita completa.
  static const okBg = Color(0xFFE6F1EA);
  static const okLine = Color(0xFFC6DDCF);
  static const okFg = Color(0xFF2F6B46);
  static const okDot = Color(0xFF3F8A5E);

  /// Rojo: fuera de rango clínico, visita perdida.
  static const dangerBg = Color(0xFFF6E7E7);
  static const dangerSurface = Color(0xFFFDF6F6);
  static const dangerLine = Color(0xFFD9A8A8);
  static const dangerFg = Color(0xFF9B2C2C);

  /// Gris: visita futura / no aplicable.
  static const idleBg = Color(0xFFF0F1F2);
  static const idleFg = Color(0xFF9AA1A8);

  /// Chip neutro: "SOLO LECTURA", "DOC. v2.1".
  static const neutralBg = Color(0xFFECEFF1);
  static const neutralLine = Color(0xFFDFE2E5);
  static const neutralFg = Color(0xFF4A5158);

  // ── Ramas del estudio ──────────────────────────────────────────
  // El color codifica la rama en toda la app; no reasignar por estética.
  static const nuevoBg = Color(0xFFE2F0ED);
  static const nuevoFg = Color(0xFF0F4F49);
  static const nuevoLine = Color(0xFFC9E2DD);
  static const vigenteBg = Color(0xFFE8EEF7);
  static const vigenteFg = Color(0xFF2C4A75);
  static const vigenteLine = Color(0xFFCDDAEB);

  // ── Panel de administración (barra lateral oscura) ─────────────
  static const sidebar = Color(0xFF16181A);
  static const sidebarActive = Color(0xFF24282C);
  static const sidebarLine = Color(0xFF2C3136);
  static const sidebarText = Color(0xFFC9CED3);
  static const sidebarMuted = Color(0xFF7D858D);

  // ── Tipografía ─────────────────────────────────────────────────
  static const sans = 'IBMPlexSans';
  static const mono = 'IBMPlexMono';

  /// Si la fuente empaquetada faltara, el texto monoespaciado debe seguir
  /// siéndolo: en las tablas clínicas la alineación de cifras es información.
  static const monoFallback = <String>['monospace', 'Courier'];

  /// Etiqueta monoespaciada en versalitas: labels de campo, encabezados
  /// de sección, metadatos. Es el recurso tipográfico distintivo del diseño.
  static TextStyle label({
    double size = 10.5,
    Color color = muted,
    FontWeight weight = FontWeight.w400,
    double tracking = 0.09,
  }) =>
      TextStyle(
        fontFamily: mono,
        fontFamilyFallback: monoFallback,
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: size * tracking,
        height: 1.2,
      );

  static const TextStyle h1 =
      TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: ink, height: 1.2);
  static const TextStyle h2 =
      TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: ink, height: 1.25);
  static const TextStyle h3 =
      TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ink, height: 1.3);
  static const TextStyle title =
      TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: ink, height: 1.3);
  static const TextStyle bodyText =
      TextStyle(fontSize: 14, color: inkSoft, height: 1.5);
  static const TextStyle small =
      TextStyle(fontSize: 12.5, color: secondary, height: 1.45);
  static const TextStyle tiny =
      TextStyle(fontSize: 11.5, color: muted, height: 1.4);

  static TextStyle get monoData => const TextStyle(
      fontFamily: mono,
      fontFamilyFallback: monoFallback,
      fontSize: 11.5,
      color: muted,
      height: 1.4);

  // ── Métrica ────────────────────────────────────────────────────
  static const radiusField = 7.0;
  static const radiusCard = 8.0;
  static const radiusPanel = 9.0;
  static const radiusPill = 20.0;
  static const gutter = 18.0;
}

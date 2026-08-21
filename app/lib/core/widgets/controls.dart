import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Banda de estado en línea: sin conexión, en cola, datos al día, aviso.
/// Es el elemento que hace visible el estado offline en toda la app.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.texto,
    this.tono = BannerTone.aviso,
    this.accion,
    this.onAccion,
    this.alineaArriba = false,
  });

  final String texto;
  final BannerTone tono;
  final String? accion;
  final VoidCallback? onAccion;

  /// Para textos de varias líneas, el punto se alinea con la primera.
  final bool alineaArriba;

  @override
  Widget build(BuildContext context) {
    final (bg, bd, fg, dot) = switch (tono) {
      BannerTone.aviso => (T.warnBg, T.warnLine, T.warnFg, T.warnDot),
      BannerTone.ok => (T.okBg, T.okLine, T.okFg, T.okDot),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: bd),
        borderRadius: BorderRadius.circular(T.radiusCard),
      ),
      child: Row(
        crossAxisAlignment:
            alineaArriba ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: EdgeInsets.only(top: alineaArriba ? 5 : 0),
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(texto,
                style: TextStyle(fontSize: 12.5, color: fg, height: 1.45)),
          ),
          if (accion != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAccion,
              child: Text(accion!,
                  style: TextStyle(
                      fontFamily: T.mono,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg)),
            ),
          ],
        ],
      ),
    );
  }
}

enum BannerTone { aviso, ok }

/// Encabezado monoespaciado de sección o etiqueta de campo.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.texto, {super.key, this.color = T.muted, this.size = 10.5});

  final String texto;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Text(texto.toUpperCase(), style: T.label(size: size, color: color));
}

/// Botón principal (fondo tinta) o secundario (contorno).
class AppButton extends StatelessWidget {
  const AppButton(this.texto,
      {super.key, this.onTap, this.primary = true, this.enabled = true});

  final String texto;
  final VoidCallback? onTap;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final activo = enabled && onTap != null;
    return Semantics(
      button: true,
      enabled: activo,
      child: GestureDetector(
        onTap: activo ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: primary ? (activo ? T.ink : T.disabled) : T.card,
            border: primary ? null : Border.all(color: T.line),
            borderRadius: BorderRadius.circular(T.radiusCard),
          ),
          child: Text(
            texto,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: primary ? T.onInk : (activo ? T.body : T.disabled),
            ),
          ),
        ),
      ),
    );
  }
}

/// Campo de texto con la etiqueta monoespaciada del diseño.
class LabeledField extends StatefulWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.mono = false,
    this.keyboardType,
    this.maxLines = 1,
    this.readOnly = false,
    this.oculto = false,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool mono;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool readOnly;

  /// Oculta lo tecleado y añade el botón para mostrarlo.
  ///
  /// Con el botón, no sin él: escribir una contraseña a ciegas en el teclado de
  /// un teléfono, de pie en una sala, es una fuente de errores gratuita.
  final bool oculto;

  final ValueChanged<String>? onSubmitted;

  @override
  State<LabeledField> createState() => _LabeledFieldState();
}

class _LabeledFieldState extends State<LabeledField> {
  bool _mostrar = false;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(widget.label),
          const SizedBox(height: 6),
          TextField(
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            maxLines: widget.oculto ? 1 : widget.maxLines,
            readOnly: widget.readOnly,
            obscureText: widget.oculto && !_mostrar,
            onSubmitted: widget.onSubmitted,
            style: TextStyle(
                fontSize: 15,
                color: T.ink,
                fontFamily: widget.mono ? T.mono : null,
                height: 1.35),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.hint,
              hintStyle: const TextStyle(fontSize: 15, color: T.faint),
              filled: true,
              fillColor: T.card,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              border: fieldBorder(T.line),
              enabledBorder: fieldBorder(T.line),
              focusedBorder: fieldBorder(T.accent, ancho: 1.5),
              suffixIcon: widget.oculto
                  ? IconButton(
                      icon: Icon(
                          _mostrar
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 19,
                          color: T.muted),
                      tooltip: _mostrar ? 'Ocultar' : 'Mostrar',
                      onPressed: () => setState(() => _mostrar = !_mostrar),
                    )
                  : null,
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ),
        ],
      );
}

/// Borde de los campos de texto, compartido por todas las pantallas.
OutlineInputBorder fieldBorder(Color color, {double ancho = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(T.radiusField),
      borderSide: BorderSide(color: color, width: ancho),
    );

/// Tarjeta blanca con borde, la superficie base de listas y paneles.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    this.acento,
    this.onTap,
    this.radio = T.radiusCard,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Franja de color a la izquierda: marca la visita que vence hoy.
  final Color? acento;
  final VoidCallback? onTap;
  final double radio;

  static const double _anchoAcento = 3;

  @override
  Widget build(BuildContext context) {
    final acento = this.acento;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Borde uniforme: Flutter no admite `borderRadius` sobre un borde con
        // lados de distinto color, así que la franja de acento se pinta dentro
        // en lugar de ser el lado izquierdo del borde.
        decoration: BoxDecoration(
          color: T.card,
          borderRadius: BorderRadius.circular(radio),
          border: Border.all(color: T.lineSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: acento == null
                  ? padding
                  : padding.copyWith(left: padding.left + _anchoAcento),
              child: child,
            ),
            if (acento != null)
              // Se estira a la altura de la tarjeta sin necesitar que la
              // tarjeta tenga altura conocida: dentro de una lista no la tiene.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _anchoAcento,
                child: ColoredBox(color: acento),
              ),
          ],
        ),
      ),
    );
  }
}

/// Píldora seleccionable: filtros de lista y catálogo de síntomas.
class SelectablePill extends StatelessWidget {
  const SelectablePill({
    super.key,
    required this.texto,
    required this.seleccionado,
    this.onTap,
    this.compacta = false,
  });

  final String texto;
  final bool seleccionado;
  final VoidCallback? onTap;
  final bool compacta;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: seleccionado,
        button: onTap != null,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: compacta ? 12 : 13, vertical: compacta ? 6 : 8),
            decoration: BoxDecoration(
              color: seleccionado ? T.ink : T.card,
              border: seleccionado ? null : Border.all(color: T.line),
              borderRadius: BorderRadius.circular(T.radiusPill),
            ),
            child: Text(
              texto,
              style: TextStyle(
                fontSize: compacta ? 12.5 : 13,
                fontWeight: seleccionado ? FontWeight.w500 : FontWeight.w400,
                color: seleccionado ? T.onInk : T.body,
              ),
            ),
          ),
        ),
      );
}

/// Barra superior de las pantallas de detalle: flecha atrás, título y un
/// distintivo opcional a la derecha.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({super.key, required this.titulo, this.trailing, this.subtitulo});

  final String titulo;
  final Widget? trailing;

  /// Segunda línea: identificación del paciente en las pantallas clínicas.
  final Widget? subtitulo;

  @override
  Size get preferredSize => Size.fromHeight(subtitulo == null ? 56 : 88);

  @override
  Widget build(BuildContext context) => AppBar(
        backgroundColor: T.card,
        surfaceTintColor: T.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: T.lineFaint)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: T.body, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: Text(titulo, style: T.h3, overflow: TextOverflow.ellipsis),
        actions: [
          if (trailing != null)
            Padding(padding: const EdgeInsets.only(right: 16), child: trailing!)
        ],
        bottom: subtitulo == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(32),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(T.gutter, 0, T.gutter, 10),
                  child: Align(alignment: Alignment.centerLeft, child: subtitulo),
                ),
              ),
      );
}

/// Barra inferior fija con los botones de acción de la pantalla.
class BottomActions extends StatelessWidget {
  const BottomActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: T.card,
          border: Border(top: BorderSide(color: T.lineFaint)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SafeArea(top: false, child: Row(children: children)),
      );
}

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/controls.dart';
import '../../domain/models/visit_form_definition.dart';

/// Control de captura de un campo, elegido según su [FieldDefinition.tipo].
///
/// Es la contrapartida de la definición configurable: añadir un tipo de campo
/// nuevo al estudio es añadir un caso aquí, no reescribir pantallas.
class FieldInput extends StatelessWidget {
  const FieldInput({
    super.key,
    required this.campo,
    required this.valor,
    required this.soloLectura,
    required this.onChanged,
    this.onCorregir,
  });

  final FieldDefinition campo;
  final Object? valor;
  final bool soloLectura;
  final ValueChanged<Object?> onChanged;

  /// Presente solo cuando el registro está cerrado y el usuario es
  /// administrador: tocar el campo abre el flujo de corrección con motivo.
  final VoidCallback? onCorregir;

  @override
  Widget build(BuildContext context) => switch (campo.tipo) {
        FieldType.seleccionMultiple => _Opciones(
            campo: campo,
            seleccion: (valor as List?)?.cast<String>() ?? const [],
            soloLectura: soloLectura,
            multiple: true,
            onChanged: onChanged,
            onCorregir: onCorregir),
        FieldType.seleccionUnica => _Opciones(
            campo: campo,
            seleccion: valor == null ? const [] : [valor as String],
            soloLectura: soloLectura,
            multiple: false,
            onChanged: onChanged,
            onCorregir: onCorregir),
        FieldType.textoLargo => _TextoLargo(
            campo: campo,
            valor: valor as String?,
            soloLectura: soloLectura,
            onChanged: onChanged,
            onCorregir: onCorregir),
        _ => _Casilla(
            campo: campo,
            valor: valor,
            soloLectura: soloLectura,
            onChanged: onChanged,
            onCorregir: onCorregir),
      };
}

/// Casilla compacta de la retícula de signos vitales. El aviso de rango se
/// muestra en el propio campo: no bloquea, informa (un 38.7 real debe poder
/// registrarse tal cual).
class _Casilla extends StatefulWidget {
  const _Casilla({
    required this.campo,
    required this.valor,
    required this.soloLectura,
    required this.onChanged,
    required this.onCorregir,
  });

  final FieldDefinition campo;
  final Object? valor;
  final bool soloLectura;
  final ValueChanged<Object?> onChanged;
  final VoidCallback? onCorregir;

  @override
  State<_Casilla> createState() => _CasillaState();
}

class _CasillaState extends State<_Casilla> {
  late final TextEditingController _c = TextEditingController(text: _texto(widget.valor));

  String _texto(Object? v) => switch (v) {
        null => '',
        num n => F.numero(n, widget.campo.decimales),
        _ => v.toString(),
      };

  @override
  void didUpdateWidget(_Casilla old) {
    super.didUpdateWidget(old);
    // El valor puede cambiar por fuera (cambio de día, corrección aplicada).
    final nuevo = _texto(widget.valor);
    if (nuevo != _c.text) _c.text = nuevo;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _emitir(String texto) {
    if (widget.campo.tipo == FieldType.numero) {
      widget.onChanged(texto.trim().isEmpty ? null : num.tryParse(texto.replaceAll(',', '.')));
    } else {
      widget.onChanged(texto.trim().isEmpty ? null : texto);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aviso = widget.campo.fueraDeRango(widget.valor);
    final vacio = widget.valor == null;

    final Color borde = aviso != null
        ? T.dangerLine
        : (vacio ? const Color(0xFFCFD3D7) : T.line);
    final Color fondo = aviso != null ? T.dangerSurface : T.card;
    final Color tinta = aviso != null ? T.dangerFg : T.ink;

    final etiqueta = Text(
      aviso == null
          ? widget.campo.etiquetaConUnidad
          : '${widget.campo.etiquetaConUnidad} · $aviso',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: aviso != null ? T.dangerFg : T.muted),
    );

    return GestureDetector(
      onTap: widget.onCorregir,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: fondo,
          border: Border.all(color: borde, width: aviso != null ? 1.5 : 1),
          borderRadius: BorderRadius.circular(T.radiusField),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            etiqueta,
            const SizedBox(height: 2),
            if (widget.soloLectura)
              Text(_c.text.isEmpty ? '—' : _c.text,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: T.mono,
                      color: _c.text.isEmpty ? T.disabled : tinta))
            else
              TextField(
                controller: _c,
                onChanged: _emitir,
                keyboardType: widget.campo.tipo == FieldType.numero
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: T.mono,
                    color: tinta),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  hintText: '—',
                  hintStyle: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: T.mono,
                      color: T.disabled),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Catálogo de opciones en píldoras (síntomas referidos y similares).
class _Opciones extends StatelessWidget {
  const _Opciones({
    required this.campo,
    required this.seleccion,
    required this.soloLectura,
    required this.multiple,
    required this.onChanged,
    required this.onCorregir,
  });

  final FieldDefinition campo;
  final List<String> seleccion;
  final bool soloLectura;
  final bool multiple;
  final ValueChanged<Object?> onChanged;
  final VoidCallback? onCorregir;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onCorregir,
        child: Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final opcion in campo.opciones)
              SelectablePill(
                texto: opcion,
                seleccionado: seleccion.contains(opcion),
                onTap: soloLectura
                    ? null
                    : () {
                        if (!multiple) {
                          onChanged(opcion);
                          return;
                        }
                        final nueva = [...seleccion];
                        nueva.contains(opcion)
                            ? nueva.remove(opcion)
                            : nueva.add(opcion);
                        onChanged(nueva);
                      },
              ),
          ],
        ),
      );
}

class _TextoLargo extends StatefulWidget {
  const _TextoLargo({
    required this.campo,
    required this.valor,
    required this.soloLectura,
    required this.onChanged,
    required this.onCorregir,
  });

  final FieldDefinition campo;
  final String? valor;
  final bool soloLectura;
  final ValueChanged<Object?> onChanged;
  final VoidCallback? onCorregir;

  @override
  State<_TextoLargo> createState() => _TextoLargoState();
}

class _TextoLargoState extends State<_TextoLargo> {
  late final TextEditingController _c = TextEditingController(text: widget.valor ?? '');

  @override
  void didUpdateWidget(_TextoLargo old) {
    super.didUpdateWidget(old);
    if ((widget.valor ?? '') != _c.text) _c.text = widget.valor ?? '';
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.soloLectura) {
      return GestureDetector(
        onTap: widget.onCorregir,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: T.card,
            border: Border.all(color: T.line),
            borderRadius: BorderRadius.circular(T.radiusField),
          ),
          child: Text(_c.text.isEmpty ? '—' : _c.text,
              style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: _c.text.isEmpty ? T.disabled : T.inkSoft)),
        ),
      );
    }
    return TextField(
      controller: _c,
      onChanged: (v) => widget.onChanged(v.trim().isEmpty ? null : v),
      maxLines: 4,
      minLines: 3,
      style: const TextStyle(fontSize: 14, height: 1.5, color: T.inkSoft),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: T.card,
        hintText: 'Sin observaciones',
        hintStyle: const TextStyle(fontSize: 14, color: T.faint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: fieldBorder(T.line),
        enabledBorder: fieldBorder(T.line),
        focusedBorder: fieldBorder(T.accent, ancho: 1.5),
      ),
    );
  }
}

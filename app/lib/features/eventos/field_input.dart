import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/controls.dart';
import '../../domain/models/estudio_form_definition.dart';

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

  /// Presente solo cuando el registro está cerrado y el usuario puede
  /// corregirlo: tocar el campo abre el flujo de corrección con motivo.
  final VoidCallback? onCorregir;

  @override
  Widget build(BuildContext context) => switch (campo.tipo) {
        FieldType.seleccionMultiple => _Opciones(
            campo: campo,
            seleccion: (valor as List?)?.cast<String>() ?? const [],
            soloLectura: soloLectura,
            multiple: true,
            onChanged: onChanged,
            onCorregir: onCorregir,
          ),
        FieldType.seleccionUnica => _Opciones(
            campo: campo,
            seleccion: valor == null ? const [] : [valor! as String],
            soloLectura: soloLectura,
            multiple: false,
            onChanged: onChanged,
            onCorregir: onCorregir,
          ),
        FieldType.siNo => _SiNo(
            campo: campo,
            valor: valor as bool?,
            soloLectura: soloLectura,
            onChanged: onChanged,
            onCorregir: onCorregir,
          ),
        FieldType.fecha => _Fecha(
            campo: campo,
            valor: valor as String?,
            soloLectura: soloLectura,
            onChanged: onChanged,
            onCorregir: onCorregir,
          ),
        FieldType.textoLargo => _TextoLargo(
            campo: campo,
            valor: valor as String?,
            soloLectura: soloLectura,
            onChanged: onChanged,
            onCorregir: onCorregir,
          ),
        _ => _Casilla(
            campo: campo,
            valor: valor,
            soloLectura: soloLectura,
            onChanged: onChanged,
            onCorregir: onCorregir,
          ),
      };
}

/// Etiqueta con aviso de rango y, si la hay, la aclaración del campo.
class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.campo, this.aviso, this.compacta = false});

  final FieldDefinition campo;
  final String? aviso;
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final texto = aviso == null
        ? campo.etiquetaConUnidad
        : '${campo.etiquetaConUnidad} · $aviso';
    final color = aviso != null ? T.dangerFg : T.muted;

    if (compacta) {
      return Text(texto,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: color));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(texto, color: color),
        if (campo.ayuda != null) ...[
          const SizedBox(height: 3),
          Text(campo.ayuda!,
              style: const TextStyle(fontSize: 11.5, color: T.faint)),
        ],
      ],
    );
  }
}

/// Casilla compacta de la retícula numérica. El aviso de rango se muestra en el
/// propio campo: no bloquea, informa — en UCI un valor extremo puede ser real
/// (CLAUDE.md §14).
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
  late final TextEditingController _c =
      TextEditingController(text: _texto(widget.valor));

  String _texto(Object? v) => switch (v) {
        null => '',
        final num n => F.numero(n, widget.campo.decimales),
        _ => v.toString(),
      };

  @override
  void didUpdateWidget(_Casilla old) {
    super.didUpdateWidget(old);
    // El valor puede cambiar por fuera (cambio de evento, corrección aplicada).
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
      widget.onChanged(
          texto.trim().isEmpty ? null : num.tryParse(texto.replaceAll(',', '.')));
    } else {
      widget.onChanged(texto.trim().isEmpty ? null : texto);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aviso = widget.campo.fueraDeRango(widget.valor);
    final vacio = widget.valor == null;

    final borde = aviso != null
        ? T.dangerLine
        : (vacio ? const Color(0xFFCFD3D7) : T.line);
    final fondo = aviso != null ? T.dangerSurface : T.card;
    final tinta = aviso != null ? T.dangerFg : T.ink;

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
            _Etiqueta(campo: widget.campo, aviso: aviso, compacta: true),
            const SizedBox(height: 2),
            if (widget.soloLectura)
              Text(_c.text.isEmpty ? '—' : _c.text,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: T.mono,
                      fontFamilyFallback: T.monoFallback,
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
                    fontFamilyFallback: T.monoFallback,
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
                      fontFamilyFallback: T.monoFallback,
                      color: T.disabled),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sí / No. Se representa con las mismas píldoras que el resto de opciones para
/// que el formulario se lea igual de arriba abajo.
class _SiNo extends StatelessWidget {
  const _SiNo({
    required this.campo,
    required this.valor,
    required this.soloLectura,
    required this.onChanged,
    required this.onCorregir,
  });

  final FieldDefinition campo;
  final bool? valor;
  final bool soloLectura;
  final ValueChanged<Object?> onChanged;
  final VoidCallback? onCorregir;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onCorregir,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Etiqueta(campo: campo),
            const SizedBox(height: 8),
            Row(children: [
              for (final opcion in const [true, false]) ...[
                SelectablePill(
                  texto: opcion ? 'Sí' : 'No',
                  seleccionado: valor == opcion,
                  onTap: soloLectura
                      ? null
                      : () => onChanged(valor == opcion ? null : opcion),
                ),
                const SizedBox(width: 8),
              ],
            ]),
          ],
        ),
      );
}

/// Fecha. Se guarda en ISO (`2026-08-14`) para que ordene bien y se exporte sin
/// ambigüedad; se muestra en el formato que lee el equipo.
class _Fecha extends StatelessWidget {
  const _Fecha({
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
  Widget build(BuildContext context) {
    final fecha = valor == null ? null : DateTime.tryParse(valor!);

    return GestureDetector(
      onTap: () async {
        if (onCorregir != null) return onCorregir!();
        if (soloLectura) return;
        final elegida = await showDatePicker(
          context: context,
          initialDate: fecha ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (elegida != null) {
          onChanged(elegida.toIso8601String().substring(0, 10));
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Etiqueta(campo: campo),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: T.card,
              border: Border.all(color: T.line),
              borderRadius: BorderRadius.circular(T.radiusField),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    fecha == null ? 'Sin fecha' : F.fechaLarga(fecha),
                    style: TextStyle(
                        fontSize: 15, color: fecha == null ? T.faint : T.ink),
                  ),
                ),
                const Icon(Icons.calendar_today_outlined, size: 16, color: T.faint),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Catálogo de opciones en píldoras.
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Etiqueta(campo: campo),
            const SizedBox(height: 8),
            Wrap(
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
                              onChanged(
                                  seleccion.contains(opcion) ? null : opcion);
                              return;
                            }
                            final nueva = [...seleccion];
                            if (nueva.contains(opcion)) {
                              nueva.remove(opcion);
                            } else {
                              nueva.add(opcion);
                            }
                            onChanged(nueva);
                          },
                  ),
              ],
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
  late final TextEditingController _c =
      TextEditingController(text: widget.valor ?? '');

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
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Etiqueta(campo: widget.campo),
          const SizedBox(height: 6),
          if (widget.soloLectura)
            GestureDetector(
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
            )
          else
            TextField(
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                border: fieldBorder(T.line),
                enabledBorder: fieldBorder(T.line),
                focusedBorder: fieldBorder(T.accent, ancho: 1.5),
              ),
            ),
        ],
      );
}

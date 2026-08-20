import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/controls.dart';
import '../../domain/models/estudio_form_definition.dart';

/// Resultado de una corrección aceptada por el usuario.
typedef Correccion = ({Object? valor, String motivo});

/// Diálogo de corrección de un campo ya registrado.
///
/// Materializa la restricción CLAUDE.md §3: no hay forma de cambiar un dato
/// registrado sin escribir un motivo. El botón permanece inhabilitado hasta que
/// lo haya, y el repositorio vuelve a exigirlo por si esta pantalla fallara.
Future<Correccion?> mostrarDialogoCorreccion(
  BuildContext context, {
  required FieldDefinition campo,
  required Object? valorActual,
}) {
  final textoOriginal = switch (valorActual) {
    null => '',
    final bool b => b ? 'Sí' : 'No',
    final num n => F.numero(n, campo.decimales),
    final List l => l.join(', '),
    _ => valorActual.toString(),
  };
  final valor = TextEditingController(text: textoOriginal);
  final motivo = TextEditingController();

  return showDialog<Correccion>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: T.surface,
      surfaceTintColor: T.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(T.radiusPanel)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Corrección con auditoría'),
          const SizedBox(height: 6),
          Text(campo.etiquetaConUnidad, style: T.h3),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const SectionLabel('Valor actual'),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  textoOriginal.isEmpty ? '—' : textoOriginal,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: T.mono,
                      fontFamilyFallback: T.monoFallback,
                      fontSize: 13,
                      decoration: TextDecoration.lineThrough,
                      color: T.dangerFg),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Valor corregido',
              controller: valor,
              mono: true,
              keyboardType: campo.tipo == FieldType.numero
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
            ),
            if (campo.opciones.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Valores admitidos: ${campo.opciones.join(' · ')}',
                  style: const TextStyle(fontSize: 11.5, color: T.faint)),
            ],
            const SizedBox(height: 14),
            LabeledField(
              label: 'Motivo de la corrección',
              controller: motivo,
              maxLines: 2,
              hint: 'Ej.: cifras transpuestas al teclear',
            ),
            const SizedBox(height: 12),
            const StatusBanner(
              texto: 'Quedará registrado el valor anterior, el nuevo, su nombre '
                  'y la fecha. El registro vuelve a la cola de envío.',
              alineaArriba: true,
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      buttonPadding: EdgeInsets.zero,
      actions: [
        // El botón se habilita en cuanto hay motivo escrito: sin motivo la
        // corrección no puede registrarse.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: motivo,
          builder: (context, valorMotivo, _) => Row(children: [
            Expanded(
              child: AppButton('Cancelar',
                  primary: false, onTap: () => Navigator.of(context).pop()),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppButton(
                'Registrar',
                enabled: valorMotivo.text.trim().isNotEmpty,
                onTap: () => Navigator.of(context).pop((
                  valor: campo.tipo == FieldType.numero
                      ? num.tryParse(valor.text.replaceAll(',', '.'))
                      : valor.text,
                  motivo: valorMotivo.text,
                )),
              ),
            ),
          ]),
        ),
      ],
    ),
  ).whenComplete(() {
    valor.dispose();
    motivo.dispose();
  });
}

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/controls.dart';
import '../eventos/paciente_timeline_screen.dart';

/// 06 · Consentimiento informado.
///
/// Deja constancia de QUÉ versión del documento firmó el paciente y CUÁNDO.
/// Sin este registro no se pueden capturar eventos clínicos: la restricción la
/// impone la capa de datos, no esta pantalla.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  final _declaraciones = <int>{};
  final _firma = SignatureController();

  @override
  void dispose() {
    _firma.dispose();
    super.dispose();
  }

  void _registrar() {
    final state = AppScope.read(context);
    state.repo.registrarConsentimiento(
      autor: state.usuarioActual,
      patientId: widget.patientId,
      firmaTrazos: _firma.trazos,
    );
    state.refrescar();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PacienteTimelineScreen(patientId: widget.patientId)));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final paciente = state.repo.paciente(widget.patientId)!;
    final doc = state.repo.config.documentoConsentimiento;

    final completo = _declaraciones.length == doc.declaraciones.length &&
        _firma.trazos.isNotEmpty;

    return Scaffold(
      backgroundColor: T.surface,
      appBar: AppTopBar(
        titulo: 'Consentimiento informado',
        subtitulo: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                  '${paciente.nombre} · HC ${paciente.numeroHistoriaClinica}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: T.secondary)),
            ),
            MetaChip('DOC. ${doc.version}'),
          ],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(T.gutter, 14, T.gutter, 16),
          children: [
            // El texto se desplaza dentro de su propio marco: el investigador
            // debe poder leerlo con el paciente delante sin perder el contexto.
            Container(
              height: 210,
              decoration: BoxDecoration(
                color: T.card,
                border: Border.all(color: T.lineSoft),
                borderRadius: BorderRadius.circular(T.radiusCard),
              ),
              child: Scrollbar(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 16),
                  children: [
                    SectionLabel(
                        'Modelo aprobado · ${doc.codigoCei} · vigente desde ${doc.vigenteDesde}',
                        size: 10,
                        color: T.faint),
                    const SizedBox(height: 9),
                    for (final p in doc.parrafos) ...[
                      Text(p,
                          style: const TextStyle(
                              fontSize: 13, color: T.inkSoft, height: 1.6)),
                      const SizedBox(height: 9),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            for (var i = 0; i < doc.declaraciones.length; i++) ...[
              _Declaracion(
                texto: doc.declaraciones[i],
                marcada: _declaraciones.contains(i),
                onTap: () => setState(() =>
                    _declaraciones.contains(i) ? _declaraciones.remove(i) : _declaraciones.add(i)),
              ),
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionLabel('Firma del paciente'),
                if (_firma.trazos.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(_firma.borrar),
                    child: Text('borrar',
                        style: T.label(size: 10.5, color: T.ghost, tracking: 0)),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            SignaturePad(
              controller: _firma,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Testigo: ${state.usuarioActual.nombre}',
                    style: T.label(size: 10.5, color: T.faint, tracking: 0)),
                Text('${F.fechaLarga(DateTime.now())} · ${F.hora(DateTime.now())}',
                    style: T.label(size: 10.5, color: T.faint, tracking: 0)),
              ],
            ),

            const SizedBox(height: 16),
            const StatusBanner(
              texto: 'El consentimiento se guarda cifrado en el dispositivo y se '
                  'envía al servidor al recuperar señal. No se podrá capturar '
                  'eventos clínicos hasta registrarlo.',
              alineaArriba: true,
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActions(children: [
        Expanded(
          child: AppButton('Registrar consentimiento',
              enabled: completo, onTap: _registrar),
        ),
      ]),
    );
  }
}

class _Declaracion extends StatelessWidget {
  const _Declaracion(
      {required this.texto, required this.marcada, required this.onTap});

  final String texto;
  final bool marcada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        checked: marcada,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 17,
                height: 17,
                margin: const EdgeInsets.only(top: 1),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: marcada ? T.ink : T.card,
                  border: marcada ? null : Border.all(color: T.line, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: marcada
                    ? const Icon(Icons.check, size: 12, color: T.onInk)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(texto,
                    style: const TextStyle(
                        fontSize: 13, color: T.inkSoft, height: 1.45)),
              ),
            ],
          ),
        ),
      );
}

/// Trazos de la firma, normalizados a 0..1 para no depender del tamaño de
/// pantalla del dispositivo que capturó.
class SignatureController {
  final List<List<({double x, double y})>> trazos = [];

  void borrar() => trazos.clear();
  void dispose() => trazos.clear();
}

class SignaturePad extends StatelessWidget {
  const SignaturePad(
      {super.key, required this.controller, required this.onChanged, this.altura = 118});

  final SignatureController controller;
  final VoidCallback onChanged;
  final double altura;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, cons) {
          final tamano = Size(cons.maxWidth, altura);

          ({double x, double y}) normaliza(Offset p) => (
                x: (p.dx / tamano.width).clamp(0.0, 1.0),
                y: (p.dy / tamano.height).clamp(0.0, 1.0),
              );

          return GestureDetector(
            onPanStart: (d) {
              controller.trazos.add([normaliza(d.localPosition)]);
              onChanged();
            },
            onPanUpdate: (d) {
              if (controller.trazos.isEmpty) return;
              controller.trazos.last.add(normaliza(d.localPosition));
              onChanged();
            },
            child: Container(
              height: altura,
              width: double.infinity,
              decoration: BoxDecoration(
                color: T.card,
                borderRadius: BorderRadius.circular(T.radiusCard),
                border: Border.all(
                    color: controller.trazos.isEmpty ? T.lineDashed : T.line,
                    width: 1.5),
              ),
              child: controller.trazos.isEmpty
                  ? Center(
                      child: Text('firmar con el dedo o el lápiz',
                          style: T.label(size: 11.5, color: T.ghost, tracking: 0)),
                    )
                  : CustomPaint(painter: _SignaturePainter(controller.trazos)),
            ),
          );
        },
      );
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.trazos);

  final List<List<({double x, double y})>> trazos;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = T.ink
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final trazo in trazos) {
      if (trazo.length < 2) continue;
      final ruta = Path()
        ..moveTo(trazo.first.x * size.width, trazo.first.y * size.height);
      for (final p in trazo.skip(1)) {
        ruta.lineTo(p.x * size.width, p.y * size.height);
      }
      canvas.drawPath(ruta, pincel);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}

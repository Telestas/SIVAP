import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/controls.dart';
import '../../domain/models/patient.dart';
import '../consent/consent_screen.dart';

/// 04 · Enrolamiento de paciente.
///
/// Captura únicamente la **ficha de identidad**. Ni un dato clínico entra aquí:
/// eso vive en los registros de visita, que son otra entidad (CLAUDE.md §1).
class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  final _nombre = TextEditingController();
  final _ci = TextEditingController();
  final _edad = TextEditingController();
  final _hc = TextEditingController();
  final _telefono = TextEditingController();
  final _direccion = TextEditingController();
  Sexo _sexo = Sexo.femenino;

  /// Se rellena al guardar. Hasta entonces no hay asignación: consumir una
  /// entrada de la secuencia de aleatorización por un formulario que quizá se
  /// abandone dejaría huecos sin paciente en la secuencia.
  Patient? _guardado;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_nombre, _ci, _edad, _hc]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_nombre, _ci, _edad, _hc, _telefono, _direccion]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _completo =>
      _nombre.text.trim().isNotEmpty &&
      _ci.text.trim().isNotEmpty &&
      int.tryParse(_edad.text.trim()) != null &&
      _hc.text.trim().isNotEmpty;

  Patient? _guardar() {
    if (_guardado != null) return _guardado;
    final state = AppScope.read(context);
    try {
      final paciente = state.repo.enrolar(
        autor: state.usuarioActual,
        nombre: _nombre.text.trim(),
        carneIdentidad: _ci.text.trim(),
        edad: int.parse(_edad.text.trim()),
        sexo: _sexo,
        numeroHistoriaClinica: _hc.text.trim(),
        telefono: _telefono.text.trim(),
        direccion: _direccion.text.trim(),
      );
      state.refrescar();
      setState(() {
        _guardado = paciente;
        _error = null;
      });
      return paciente;
    } on Exception catch (e) {
      setState(() => _error = e.toString());
      return null;
    }
  }

  void _irAConsentimiento() {
    final paciente = _guardar();
    if (paciente == null || !mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ConsentScreen(patientId: paciente.id)));
  }

  @override
  Widget build(BuildContext context) {
    final config = AppScope.of(context).repo.config;

    return Scaffold(
      backgroundColor: T.surface,
      appBar: AppTopBar(
        titulo: 'Enrolar paciente',
        trailing: MetaChip(_guardado == null ? 'BORRADOR' : 'GUARDADO',
            tono: _guardado == null ? MetaTone.aviso : MetaTone.ok),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(T.gutter, 16, T.gutter, 16),
          children: [
            // Restricción CLAUDE.md §8. El flag lo controla la configuración
            // del estudio, no el código ni el investigador.
            if (!config.consentimientoAprobadoPorCei) ...[
              const StatusBanner(
                texto: 'Modo demostración: el CEI aún no aprobó protocolo ni '
                    'consentimiento. Lo que registre aquí no constituye un '
                    'enrolamiento válido del estudio.',
                alineaArriba: true,
              ),
              const SizedBox(height: 16),
            ],
            LabeledField(label: 'Nombre y apellidos', controller: _nombre),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    flex: 14,
                    child: LabeledField(
                        label: 'Carné de identidad',
                        controller: _ci,
                        mono: true,
                        keyboardType: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(
                    flex: 10,
                    child: LabeledField(
                        label: 'Edad',
                        controller: _edad,
                        keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 16),
            LabeledField(
                label: 'Núm. de historia clínica', controller: _hc, mono: true),
            const SizedBox(height: 16),
            const SectionLabel('Sexo'),
            const SizedBox(height: 8),
            Row(children: [
              for (final s in Sexo.values) ...[
                SelectablePill(
                  texto: s == Sexo.femenino ? 'Femenino' : 'Masculino',
                  seleccionado: _sexo == s,
                  onTap: () => setState(() => _sexo = s),
                ),
                const SizedBox(width: 8),
              ],
            ]),
            const SizedBox(height: 16),
            LabeledField(
                label: 'Contacto y dirección',
                controller: _telefono,
                keyboardType: TextInputType.phone,
                hint: 'Teléfono'),
            const SizedBox(height: 8),
            TextField(
              controller: _direccion,
              maxLines: 2,
              style: const TextStyle(fontSize: 14, color: T.body, height: 1.4),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Dirección',
                hintStyle: const TextStyle(fontSize: 14, color: T.faint),
                filled: true,
                fillColor: T.card,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                border: fieldBorder(T.line),
                enabledBorder: fieldBorder(T.line),
                focusedBorder: fieldBorder(T.accent, ancho: 1.5),
              ),
            ),
            const SizedBox(height: 20),
            _PanelAsignacion(paciente: _guardado),
            if (_error != null) ...[
              const SizedBox(height: 14),
              StatusBanner(texto: _error!, alineaArriba: true),
            ],
            if (_guardado != null && !_guardado!.tieneConsentimiento) ...[
              const SizedBox(height: 14),
              StatusBanner(
                texto: 'Falta el consentimiento informado',
                accion: 'FIRMAR',
                onAccion: _irAConsentimiento,
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomActions(children: [
        Expanded(
          flex: 10,
          child: AppButton('Guardar',
              primary: false,
              enabled: _completo && _guardado == null,
              onTap: _guardar),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 14,
          child: AppButton('Ir a consentimiento',
              enabled: _completo, onTap: _irAConsentimiento),
        ),
      ]),
    );
  }
}

/// Panel de asignación de rama.
///
/// Deliberadamente sin ningún control: el investigador no elige el protocolo.
/// Si esta pantalla algún día ofrece un selector, el estudio deja de ser
/// aleatorizado (CLAUDE.md §4).
class _PanelAsignacion extends StatelessWidget {
  const _PanelAsignacion({required this.paciente});

  final Patient? paciente;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF5F3),
          border: Border.all(color: const Color(0xFFCFE0DC)),
          borderRadius: BorderRadius.circular(T.radiusPanel),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionLabel('Asignación por aleatorización', color: T.body),
                if (paciente != null)
                  Text(paciente!.bloqueAleatorizacion,
                      style: T.label(size: 10.5, color: T.secondary, tracking: 0)),
              ],
            ),
            const SizedBox(height: 10),
            if (paciente == null)
              const Text(
                  'La rama se asigna automáticamente al guardar la ficha, '
                  'tomando la siguiente entrada de la secuencia aleatoria del '
                  'estudio.',
                  style: TextStyle(fontSize: 12.5, color: T.secondary, height: 1.45))
            else
              Row(
                children: [
                  ProtocolChip(paciente!.protocolo, largo: true, fontSize: 12),
                  const SizedBox(width: 11),
                  // Solo la letra y la hora. Ninguna descripción de la rama:
                  // el sistema no sabe cuál es cuál (CLAUDE.md §2).
                  Expanded(
                    child: Text('Asignado a las ${F.hora(paciente!.asignadoEn)}',
                        style: const TextStyle(
                            fontSize: 12.5, color: T.secondary, height: 1.4)),
                  ),
                ],
              ),
            const SizedBox(height: 9),
            const Divider(height: 1, color: Color(0xFFDBE6E3)),
            const SizedBox(height: 9),
            const Text(
                'La asignación es automática y no puede modificarse. El sistema '
                'no registra a qué protocolo corresponde cada rama.',
                style: TextStyle(fontSize: 12, color: T.secondary, height: 1.5)),
          ],
        ),
      );
}

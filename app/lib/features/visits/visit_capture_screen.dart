import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/controls.dart';
import '../../domain/models/visit.dart';
import '../../domain/models/visit_form_definition.dart';
import 'correction_dialog.dart';
import 'field_input.dart';

/// 05 · Captura de visita por día.
///
/// El cuerpo del formulario NO está escrito a mano: se construye recorriendo
/// [VisitFormDefinition] (CLAUDE.md §3). Añadir, quitar o restringir un campo a
/// ciertos días es editar esa definición — esta pantalla no cambia.
class VisitCaptureScreen extends StatefulWidget {
  const VisitCaptureScreen({super.key, required this.patientId, this.diaInicial});

  final String patientId;
  final int? diaInicial;

  @override
  State<VisitCaptureScreen> createState() => _VisitCaptureScreenState();
}

class _VisitCaptureScreenState extends State<VisitCaptureScreen> {
  late int _dia;

  /// Valores en edición del día visible. Se recargan al cambiar de pestaña.
  Map<String, Object?> _valores = {};
  bool _sucio = false;

  @override
  void initState() {
    super.initState();
    final repo = AppScope.read(context).repo;
    final visitas = repo.visitasDe(widget.patientId);
    _dia = widget.diaInicial ??
        visitas
            .firstWhere((v) => !v.status.esInmutable, orElse: () => visitas.first)
            .dia;
    _cargar();
  }

  void _cargar() {
    final repo = AppScope.read(context).repo;
    _valores = Map.of(repo.visita(widget.patientId, _dia)?.valores ?? const {});
    _sucio = false;
  }

  void _cambiarDia(int dia) {
    if (dia == _dia) return;
    setState(() {
      _dia = dia;
      _cargar();
    });
  }

  void _guardarBorrador() {
    final state = AppScope.read(context);
    state.repo.guardarBorrador(
      autor: state.usuarioActual,
      patientId: widget.patientId,
      dia: _dia,
      valores: _valores,
    );
    state.refrescar();
    setState(() => _sucio = false);
    _avisar('Borrador guardado en el dispositivo.');
  }

  void _cerrarVisita(List<FieldDefinition> campos) {
    final faltan = campos
        .where((c) => c.obligatorio && _vacio(_valores[c.key]))
        .map((c) => c.label)
        .toList();
    if (faltan.isNotEmpty) {
      _avisar('Faltan campos obligatorios: ${faltan.join(', ')}.');
      return;
    }
    final state = AppScope.read(context);
    state.repo.cerrarVisita(
      autor: state.usuarioActual,
      patientId: widget.patientId,
      dia: _dia,
      valores: _valores,
    );
    state.refrescar();
    setState(_cargar);
    _avisar('Visita cerrada y puesta en cola de envío.');
  }

  static bool _vacio(Object? v) =>
      v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);

  void _avisar(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto, style: const TextStyle(fontSize: 13)),
      backgroundColor: T.ink,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _corregir(FieldDefinition campo) async {
    final state = AppScope.read(context);
    final resultado = await mostrarDialogoCorreccion(
      context,
      campo: campo,
      valorActual: _valores[campo.key],
    );
    if (resultado == null || !mounted) return;

    state.repo.corregirVisitaEnviada(
      autor: state.usuarioActual,
      patientId: widget.patientId,
      dia: _dia,
      campo: campo.key,
      valorNuevo: resultado.valor,
      motivo: resultado.motivo,
    );
    state.refrescar();
    setState(_cargar);
    _avisar('Corrección registrada en auditoría.');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final paciente = state.repo.paciente(widget.patientId)!;
    final definicion = state.repo.config.definicionFormulario;
    final visita = state.repo.visita(widget.patientId, _dia)!;
    final secciones = definicion.seccionesPara(_dia);
    final campos = definicion.camposPara(_dia).toList();

    final cerrada = visita.status.esInmutable;
    final puedeCorregir =
        cerrada && state.usuarioActual.role.puedeCorregirEnviado;
    final soloLectura = cerrada || !state.usuarioActual.role.puedeCapturarVisitas;

    return Scaffold(
      backgroundColor: T.surface,
      appBar: AppTopBar(
        titulo: paciente.nombre,
        trailing: ProtocolChip(paciente.protocolo),
        subtitulo: Text(
            'HC ${paciente.numeroHistoriaClinica} · ${paciente.demografia}',
            style: T.monoData),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              color: T.card,
              padding: const EdgeInsets.fromLTRB(T.gutter, 0, T.gutter, 10),
              child: Column(
                children: [
                  if (state.sinConexion)
                    StatusBanner(
                      texto: 'Sin conexión · guardando en el dispositivo',
                      accion: state.textoSyncCorto,
                      onAccion: state.alternarConexion,
                    )
                  else
                    StatusBanner(
                      texto: 'Conectado · los cambios se envían al cerrar la visita',
                      tono: BannerTone.ok,
                      accion: state.textoSyncCorto,
                      onAccion: state.alternarConexion,
                    ),
                  const SizedBox(height: 10),
                  _PestanasDia(
                    dias: definicion.diasVisita,
                    seleccionado: _dia,
                    onSelect: _cambiarDia,
                  ),
                ],
              ),
            ),
            Container(height: 1, color: T.lineFaint),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(T.gutter, 14, T.gutter, 20),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          'Día $_dia · ${F.fechaLarga(visita.fechaProgramada)}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, color: T.ink)),
                      MetaChip(visita.status.etiqueta,
                          tono: switch (visita.status) {
                            VisitStatus.enviada => MetaTone.ok,
                            VisitStatus.perdida => MetaTone.neutro,
                            _ => MetaTone.aviso,
                          }),
                    ],
                  ),
                  if (cerrada) ...[
                    const SizedBox(height: 12),
                    StatusBanner(
                      texto: puedeCorregir
                          ? 'Visita ya enviada. Toque un campo para corregirlo: '
                              'se le pedirá el motivo y quedará en auditoría.'
                          : 'Visita ya enviada. No admite cambios; solicite la '
                              'corrección al administrador.',
                      tono: BannerTone.ok,
                      alineaArriba: true,
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Aquí ocurre lo importante: el formulario es un recorrido
                  // sobre la definición, no una lista de widgets a mano.
                  for (final seccion in secciones) ...[
                    SectionLabel(seccion.titulo),
                    const SizedBox(height: 9),
                    _Seccion(
                      campos: seccion.campos,
                      valores: _valores,
                      soloLectura: soloLectura,
                      onChanged: (key, valor) => setState(() {
                        _valores[key] = valor;
                        _sucio = true;
                      }),
                      onCorregir: puedeCorregir ? _corregir : null,
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: soloLectura
          ? null
          : BottomActions(children: [
              Expanded(
                flex: 10,
                child: AppButton('Borrador',
                    primary: false, enabled: _sucio, onTap: _guardarBorrador),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 15,
                child: AppButton('Cerrar visita',
                    onTap: () => _cerrarVisita(campos)),
              ),
            ]),
    );
  }
}

/// Pestañas de día. Se generan desde `diasVisita`: si el protocolo cambia a
/// cuatro visitas, esta fila lo refleja sin tocar código.
class _PestanasDia extends StatelessWidget {
  const _PestanasDia(
      {required this.dias, required this.seleccionado, required this.onSelect});

  final List<int> dias;
  final int seleccionado;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (final d in dias) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(d),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  decoration: BoxDecoration(
                    color: d == seleccionado ? T.ink : const Color(0xFFF1F2F3),
                    border: Border.all(
                        color: d == seleccionado ? T.ink : T.lineFaint),
                    borderRadius: BorderRadius.circular(T.radiusField),
                  ),
                  child: Text('Día $d',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: d == seleccionado ? T.onInk : T.secondary)),
                ),
              ),
            ),
            if (d != dias.last) const SizedBox(width: 6),
          ],
        ],
      );
}

/// Distribuye los campos de una sección en la retícula de dos columnas.
class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.campos,
    required this.valores,
    required this.soloLectura,
    required this.onChanged,
    required this.onCorregir,
  });

  final List<FieldDefinition> campos;
  final Map<String, Object?> valores;
  final bool soloLectura;
  final void Function(String key, Object? valor) onChanged;
  final void Function(FieldDefinition campo)? onCorregir;

  @override
  Widget build(BuildContext context) {
    final filas = <Widget>[];
    var i = 0;
    while (i < campos.length) {
      final campo = campos[i];
      if (campo.ancho == 2) {
        filas.add(_input(campo));
        i++;
        continue;
      }
      final siguiente = i + 1 < campos.length && campos[i + 1].ancho == 1
          ? campos[i + 1]
          : null;
      filas.add(Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _input(campo)),
          const SizedBox(width: 9),
          Expanded(child: siguiente == null ? const SizedBox() : _input(siguiente)),
        ],
      ));
      i += siguiente == null ? 1 : 2;
    }

    return Column(
      children: [
        for (var f = 0; f < filas.length; f++) ...[
          filas[f],
          if (f != filas.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _input(FieldDefinition campo) => FieldInput(
        campo: campo,
        valor: valores[campo.key],
        soloLectura: soloLectura,
        onChanged: (v) => onChanged(campo.key, v),
        onCorregir: onCorregir == null ? null : () => onCorregir!(campo),
      );
}

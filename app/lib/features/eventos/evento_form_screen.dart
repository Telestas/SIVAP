import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/controls.dart';
import '../../domain/models/estudio_form_definition.dart';
import '../../domain/models/evento_clinico.dart';
import 'correction_dialog.dart';
import 'field_input.dart';

/// Captura de un evento clínico.
///
/// El cuerpo del formulario NO está escrito a mano: se construye recorriendo la
/// [EventoDefinicion] del tipo (CLAUDE.md §5). Añadir, quitar o reordenar
/// campos es editar esa definición — esta pantalla no cambia.
class EventoFormScreen extends StatefulWidget {
  /// Abre el formulario de una ocurrencia nueva de [tipo].
  const EventoFormScreen.nuevo({
    super.key,
    required this.patientId,
    required this.tipo,
  }) : eventoId = null;

  /// Abre un evento existente: borrador para seguir capturando, o registrado
  /// para consultar y —si el rol lo permite— corregir.
  const EventoFormScreen.existente({
    super.key,
    required this.patientId,
    required this.tipo,
    required this.eventoId,
  });

  final String patientId;
  final TipoEvento tipo;
  final String? eventoId;

  @override
  State<EventoFormScreen> createState() => _EventoFormScreenState();
}

class _EventoFormScreenState extends State<EventoFormScreen> {
  late Map<String, Object?> _valores;
  late DateTime _fechaOcurrencia;
  String? _eventoId;
  bool _sucio = false;

  @override
  void initState() {
    super.initState();
    _eventoId = widget.eventoId;
    _cargar();
  }

  void _cargar() {
    final repo = AppScope.read(context).repo;
    final existente = _eventoId == null ? null : repo.evento(_eventoId!);
    _valores = Map.of(existente?.valores ?? const {});
    _fechaOcurrencia = existente?.fechaOcurrencia ?? DateTime.now();
    _sucio = false;
  }

  EventoClinico? get _evento =>
      _eventoId == null ? null : AppScope.read(context).repo.evento(_eventoId!);

  void _avisar(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto, style: const TextStyle(fontSize: 13)),
      backgroundColor: T.ink,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _guardarBorrador() {
    final state = AppScope.read(context);
    try {
      final e = state.repo.guardarBorrador(
        autor: state.usuarioActual,
        patientId: widget.patientId,
        tipo: widget.tipo,
        fechaOcurrencia: _fechaOcurrencia,
        valores: _valores,
      );
      state.refrescar();
      setState(() {
        _eventoId = e.id;
        _sucio = false;
      });
      _avisar('Borrador guardado en el dispositivo.');
    } on Exception catch (error) {
      _avisar(error.toString());
    }
  }

  void _registrar(EventoDefinicion definicion) {
    // Solo se exige lo que está a la vista. Un campo oculto obligatorio
    // bloquearía el formulario por algo que la pantalla ni enseña.
    final faltan = definicion
        .obligatoriosVisibles(_valores)
        .where((c) => _vacio(_valores[c.key]))
        .map((c) => c.label)
        .toList();
    if (faltan.isNotEmpty) {
      _avisar('Faltan campos obligatorios: ${faltan.join(', ')}.');
      return;
    }
    final state = AppScope.read(context);
    try {
      state.repo.registrarEvento(
        autor: state.usuarioActual,
        patientId: widget.patientId,
        tipo: widget.tipo,
        fechaOcurrencia: _fechaOcurrencia,
        valores: _valores,
      );
      state.refrescar();
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (error) {
      _avisar(error.toString());
    }
  }

  static bool _vacio(Object? v) =>
      v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);

  /// Rehace lo que depende de otros campos, después de cada cambio.
  ///
  /// Dos cosas, y el orden importa. Primero se borra lo que ha dejado de
  /// verse: quien contesta «Fallo», elige una causa y luego rectifica a
  /// «Éxito» no debe dejar la causa guardada por detrás. Después se recalculan
  /// el IMC y los suyos, que pueden depender de lo que se acaba de escribir.
  void _recalcular(EventoDefinicion definicion) {
    for (final campo in definicion.campos) {
      if (!campo.visibleCon(_valores)) _valores.remove(campo.key);
    }
    for (final campo in definicion.campos) {
      if (!campo.esCalculado) continue;
      final valor = Calculos.resolver(campo, _valores);
      if (valor == null) {
        _valores.remove(campo.key);
      } else {
        _valores[campo.key] = valor;
      }
    }
  }

  Future<void> _corregir(FieldDefinition campo) async {
    final state = AppScope.read(context);
    final resultado = await mostrarDialogoCorreccion(
      context,
      campo: campo,
      valorActual: _valores[campo.key],
    );
    if (resultado == null || !mounted) return;

    state.repo.corregirEventoRegistrado(
      autor: state.usuarioActual,
      eventoId: _eventoId!,
      campo: campo.key,
      valorNuevo: resultado.valor,
      motivo: resultado.motivo,
    );
    state.refrescar();
    setState(_cargar);
    _avisar('Corrección registrada en auditoría.');
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fechaOcurrencia,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (elegida != null) {
      setState(() {
        _fechaOcurrencia = elegida;
        _sucio = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final paciente = state.repo.paciente(widget.patientId)!;
    final definicion = state.repo.config.definicionFormulario.para(widget.tipo);
    final evento = _evento;

    final usuario = state.usuarioActual;
    final cerrado = evento?.estado.esInmutable ?? false;
    final puedeCorregir = cerrado && usuario.puedeCorregirRegistrado;
    final soloLectura = cerrado || !usuario.puedeCapturar(widget.tipo);

    if (definicion == null) {
      return Scaffold(
        backgroundColor: T.surface,
        appBar: AppTopBar(titulo: widget.tipo.etiqueta),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'Este hito todavía no tiene formulario definido. Se añade en la '
              'definición del estudio, no en el código de la app.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: T.faint, height: 1.5),
            ),
          ),
        ),
      );
    }


    return Scaffold(
      backgroundColor: T.surface,
      appBar: AppTopBar(
        titulo: evento?.referencia ?? widget.tipo.etiqueta,
        // El evaluador de desenlaces no ve la rama (BASES §4).
        trailing: usuario.veRamaAsignada
            ? ProtocolChip(paciente.protocolo)
            : const MetaChip('RAMA OCULTA'),
        subtitulo: Text('${paciente.codigo} · ${paciente.demografia}',
            style: T.monoData),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(T.gutter, 14, T.gutter, 20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.tipo.cuando,
                      style: const TextStyle(
                          fontSize: 12.5, color: T.secondary, height: 1.4)),
                ),
                const SizedBox(width: 10),
                MetaChip(
                  evento?.estado.etiqueta ?? 'NUEVO',
                  tono: switch (evento?.estado) {
                    EstadoEvento.registrado => MetaTone.ok,
                    EstadoEvento.borrador => MetaTone.aviso,
                    null => MetaTone.neutro,
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // La fecha del hito la declara quien captura: es cuándo ocurrió, no
            // cuándo se tecleó. Se captura sin conexión, a veces al final del
            // turno (CLAUDE.md §4).
            _FechaOcurrencia(
              fecha: _fechaOcurrencia,
              soloLectura: soloLectura,
              onTap: _elegirFecha,
            ),
            const SizedBox(height: 18),

            if (cerrado) ...[
              StatusBanner(
                texto: puedeCorregir
                    ? 'Evento ya registrado. Toque un campo para corregirlo: '
                        'se le pedirá el motivo y quedará en auditoría.'
                    : 'Evento ya registrado. No admite cambios; solicite la '
                        'corrección al investigador principal.',
                tono: BannerTone.ok,
                alineaArriba: true,
              ),
              const SizedBox(height: 18),
            ],

            // Aquí ocurre lo importante: el formulario es un recorrido sobre la
            // definición, no una lista de widgets a mano.
            for (final seccion in definicion.secciones) ...[
              // La puerta de exclusión no se repite aquí: se contestó en el
              // enrolamiento, antes de que el paciente existiera. Volver a
              // preguntarla sería pedir dos veces lo mismo, y todo paciente
              // enrolado la contestó igual — por eso no se guarda.
              //
              // Y una sección cuyos campos están todos ocultos no se pinta: un
              // título suelto sin nada debajo hace pensar que falta algo.
              if (!seccion.esPuertaDeExclusion &&
                  seccion.campos.any((c) => c.visibleCon(_valores))) ...[
                SectionLabel(seccion.titulo),
                const SizedBox(height: 9),
                _Seccion(
                  campos: seccion.campos
                      .where((c) => c.visibleCon(_valores))
                      .toList(),
                  valores: _valores,
                  soloLectura: soloLectura,
                  onChanged: (key, valor) => setState(() {
                    _valores[key] = valor;
                    _recalcular(definicion);
                    _sucio = true;
                  }),
                  onCorregir: puedeCorregir ? _corregir : null,
                ),
                const SizedBox(height: 20),
              ],
            ],
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
                child: AppButton('Registrar',
                    onTap: () => _registrar(definicion)),
              ),
            ]),
    );
  }
}

class _FechaOcurrencia extends StatelessWidget {
  const _FechaOcurrencia({
    required this.fecha,
    required this.soloLectura,
    required this.onTap,
  });

  final DateTime fecha;
  final bool soloLectura;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: soloLectura ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: T.accentTint,
            border: Border.all(color: const Color(0xFFCFE0DC)),
            borderRadius: BorderRadius.circular(T.radiusField),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('Fecha en que ocurrió', color: T.body),
                    const SizedBox(height: 4),
                    Text(F.fechaLarga(fecha),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: T.ink)),
                  ],
                ),
              ),
              if (!soloLectura)
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: T.body),
            ],
          ),
        ),
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
      final siguiente =
          i + 1 < campos.length && campos[i + 1].ancho == 1 ? campos[i + 1] : null;
      // `start` y no `stretch`: dentro de una lista la fila no tiene altura
      // acotada, y estirar al alto de la fila pediría altura infinita.
      filas.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          if (f != filas.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  // Un campo calculado se muestra pero no se edita: si el IMC no cuadra, lo
  // que hay que corregir es el peso o la talla.
  Widget _input(FieldDefinition campo) => FieldInput(
        campo: campo,
        valor: valores[campo.key],
        soloLectura: soloLectura || campo.esCalculado,
        onChanged: (v) => onChanged(campo.key, v),
        onCorregir: onCorregir == null ? null : () => onCorregir!(campo),
      );
}

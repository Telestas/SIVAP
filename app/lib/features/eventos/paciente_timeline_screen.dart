import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/controls.dart';
import '../../domain/models/evento_clinico.dart';
import 'evento_form_screen.dart';

/// Línea de tiempo del paciente por fases del proceso de liberación.
///
/// Sustituye a las pestañas fijas de día del modelo anterior. Aquí no hay
/// calendario: hay fases, y dentro de cada fase los hitos que pueden ocurrir,
/// con las ocurrencias que ya se registraron. Un hito que no ocurrió no aparece
/// como ausencia — simplemente no tiene registros (CLAUDE.md §4).
class PacienteTimelineScreen extends StatelessWidget {
  const PacienteTimelineScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final paciente = state.repo.paciente(patientId)!;
    final eventos = state.repo.eventosDe(patientId);
    final definicion = state.repo.config.definicionFormulario;
    final usuario = state.usuarioActual;

    return Scaffold(
      backgroundColor: T.surface,
      appBar: AppTopBar(
        titulo: paciente.codigo,
        // El evaluador de desenlaces no ve la rama (BASES §4).
        trailing: usuario.veRamaAsignada
            ? ProtocolChip(paciente.protocolo)
            : const MetaChip('RAMA OCULTA'),
        subtitulo: Text(
            '${paciente.nombre} · ${paciente.demografia} · '
            '${paciente.institucion.codigo}',
            style: T.monoData),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(T.gutter, 12, T.gutter, 28),
          children: [
            if (state.sinConexion)
              StatusBanner(
                texto: 'Sin conexión · guardando en el dispositivo',
                accion: state.textoSyncCorto,
                onAccion: state.alternarConexion,
              )
            else
              StatusBanner(
                texto: 'Conectado · los registros se envían al cerrarlos',
                tono: BannerTone.ok,
                accion: state.textoSyncCorto,
                onAccion: state.alternarConexion,
              ),
            const SizedBox(height: 8),

            for (final fase in FaseEstudio.values) ...[
              _Fase(
                fase: fase,
                patientId: patientId,
                eventos: eventos.where((e) => e.tipo.fase == fase).toList(),
                // La captura va por tipo de hito, no por «puede escribir»: el
                // aplicador registra las fases del protocolo y el evaluador los
                // desenlaces. Es la separación de funciones del ensayo, no una
                // jerarquía de permisos (BASES §4).
                puedeCapturar: (t) =>
                    usuario.puedeCapturar(t) && definicion.tieneFormulario(t),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fase extends StatelessWidget {
  const _Fase({
    required this.fase,
    required this.patientId,
    required this.eventos,
    required this.puedeCapturar,
  });

  final FaseEstudio fase;
  final String patientId;
  final List<EventoClinico> eventos;
  final bool Function(TipoEvento) puedeCapturar;

  @override
  Widget build(BuildContext context) {
    final tipos = TipoEvento.deFase(fase);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: SectionLabel(fase.etiqueta)),
            FasePill(
              fase: fase,
              registrados:
                  eventos.where((e) => e.estado.esInmutable).length,
              enBorrador: eventos.any((e) => !e.estado.esInmutable),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final tipo in tipos) ...[
          _Hito(
            tipo: tipo,
            patientId: patientId,
            ocurrencias: eventos.where((e) => e.tipo == tipo).toList(),
            puedeCapturar: puedeCapturar(tipo),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _Hito extends StatelessWidget {
  const _Hito({
    required this.tipo,
    required this.patientId,
    required this.ocurrencias,
    required this.puedeCapturar,
  });

  final TipoEvento tipo;
  final String patientId;
  final List<EventoClinico> ocurrencias;
  final bool puedeCapturar;

  /// Un hito no repetible ya registrado no admite otra ocurrencia: si el dato
  /// es incorrecto se corrige, no se duplica.
  bool get _admiteOtra =>
      tipo.repetible || !ocurrencias.any((e) => e.estado.esInmutable);

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tipo.etiqueta, style: T.title),
                      const SizedBox(height: 3),
                      Text(tipo.cuando, style: T.tiny),
                    ],
                  ),
                ),
                if (tipo.repetible) ...[
                  const SizedBox(width: 10),
                  const MetaChip('REPETIBLE'),
                ],
              ],
            ),
            if (ocurrencias.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1, color: T.lineHair),
              for (final e in ocurrencias) _Ocurrencia(evento: e),
            ],
            if (puedeCapturar && _admiteOtra) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EventoFormScreen.nuevo(
                      patientId: patientId, tipo: tipo),
                )),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    const Icon(Icons.add, size: 15, color: T.accent),
                    const SizedBox(width: 6),
                    Text(
                      ocurrencias.isEmpty
                          ? 'Registrar'
                          : 'Registrar otro ${tipo.sustantivoOcurrencia}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: T.accent),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}

class _Ocurrencia extends StatelessWidget {
  const _Ocurrencia({required this.evento});

  final EventoClinico evento;

  @override
  Widget build(BuildContext context) {
    final borrador = !evento.estado.esInmutable;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EventoFormScreen.existente(
          patientId: evento.patientId,
          tipo: evento.tipo,
          eventoId: evento.id,
        ),
      )),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            SyncDot(evento.sync),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                evento.tipo.repetible
                    ? '${_capitalizar(evento.tipo.sustantivoOcurrencia)} '
                        '${evento.ocurrencia} · ${F.diaMes(evento.fechaOcurrencia)}'
                    : F.fechaLarga(evento.fechaOcurrencia),
                style: T.small,
              ),
            ),
            if (evento.correcciones > 0) ...[
              Text(
                '${evento.correcciones} corr.',
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: T.accent),
              ),
              const SizedBox(width: 8),
            ],
            MetaChip(evento.estado.etiqueta,
                tono: borrador ? MetaTone.aviso : MetaTone.ok),
          ],
        ),
      ),
    );
  }

  static String _capitalizar(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

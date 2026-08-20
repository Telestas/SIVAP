import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/collections.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/controls.dart';
import '../../data/local/seed_data.dart';
import '../../domain/models/evento_clinico.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/protocolo.dart';
import '../consent/consent_screen.dart';
import '../enrollment/enrollment_screen.dart';
import '../eventos/paciente_timeline_screen.dart';

/// Lista de pacientes, con dos caras: la carga del recolector y la cohorte
/// completa en solo lectura para el observador. Es la misma información leída
/// con permisos distintos.
class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

/// Filtros de la lista.
///
/// No hay «visita de hoy»: en un ensayo dirigido por eventos nadie sabe de
/// antemano qué toca. Lo que sí se puede saber es qué quedó a medias y de quién
/// no hay nada registrado hoy, que es lo que de verdad necesita el equipo.
enum _Filtro { todos, conBorrador, sinRegistroHoy }

class _PatientListScreenState extends State<PatientListScreen> {
  _Filtro _filtro = _Filtro.todos;
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final usuario = state.usuarioActual;
    // Quien no captura ni enrola solo consulta: observador y analista.
    final soloLectura = !usuario.puedeCapturarEventos && !usuario.puedeEnrolar;

    final propios = state.repo.pacientes(
        recolectorId: usuario.veCohorteCompleta ? null : usuario.id);
    final visibles = propios.where((p) => _coincide(state, p)).toList();

    return Scaffold(
      backgroundColor: T.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Encabezado(
              soloLectura: soloLectura,
              total: propios.length,
              filtro: _filtro,
              onFiltro: (f) => setState(() => _filtro = f),
              onBuscar: (v) => setState(() => _busqueda = v),
            ),
            Expanded(
              child: soloLectura
                  ? _ListaCohorte(pacientes: visibles)
                  : _ListaCarga(pacientes: visibles),
            ),
          ],
        ),
      ),
      bottomNavigationBar: usuario.puedeEnrolar
          ? BottomActions(children: [
              Expanded(
                child: AppButton('+ Enrolar paciente',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const EnrollmentScreen()))),
              ),
            ])
          : null,
    );
  }

  bool _coincide(AppState state, Patient p) {
    final q = _busqueda.trim().toLowerCase();
    if (q.isNotEmpty &&
        !p.nombre.toLowerCase().contains(q) &&
        !p.codigo.toLowerCase().contains(q) &&
        !p.numeroHistoriaClinica.toLowerCase().contains(q)) {
      return false;
    }
    final eventos = state.repo.eventosDe(p.id);
    return switch (_filtro) {
      _Filtro.todos => true,
      _Filtro.conBorrador => eventos.any((e) => !e.estado.esInmutable),
      _Filtro.sinRegistroHoy => !eventos
          .any((e) => F.diasEntre(Seed.hoy, e.fechaOcurrencia) == 0),
    };
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.soloLectura,
    required this.total,
    required this.filtro,
    required this.onFiltro,
    required this.onBuscar,
  });

  final bool soloLectura;
  final int total;
  final _Filtro filtro;
  final ValueChanged<_Filtro> onFiltro;
  final ValueChanged<String> onBuscar;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final usuario = state.usuarioActual;

    return Container(
      decoration: const BoxDecoration(
        color: T.card,
        border: Border(bottom: BorderSide(color: T.lineFaint)),
      ),
      padding: const EdgeInsets.fromLTRB(T.gutter, 8, T.gutter, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(soloLectura ? 'Cohorte completa' : 'Mis pacientes',
                        style: T.h2),
                    const SizedBox(height: 2),
                    Text('${usuario.nombre} · ${usuario.etiquetaRoles}',
                        style: const TextStyle(fontSize: 12, color: T.secondary)),
                  ],
                ),
              ),
              if (soloLectura)
                const MetaChip('SOLO LECTURA')
              else
                GestureDetector(
                  onTap: state.cerrarSesion,
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        color: Color(0xFFE6E8EA), shape: BoxShape.circle),
                    child: Text(usuario.iniciales,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: T.body)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.sinConexion)
            StatusBanner(
              texto: '${state.textoSync} · se enviará al recuperar señal',
              accion: 'VER',
              onAccion: state.alternarConexion,
            )
          else
            StatusBanner(
              texto: state.textoSync,
              tono: BannerTone.ok,
              accion: 'VER',
              onAccion: state.alternarConexion,
            ),
          if (soloLectura) ...[
            const SizedBox(height: 12),
            const _ResumenRamas(),
          ],
          const SizedBox(height: 12),
          TextField(
            onChanged: onBuscar,
            style: const TextStyle(fontSize: 14, color: T.ink),
            decoration: InputDecoration(
              isDense: true,
              hintText: soloLectura
                  ? 'Buscar en $total pacientes'
                  : 'Buscar por código, nombre o historia clínica',
              hintStyle: const TextStyle(fontSize: 14, color: T.faint),
              filled: true,
              fillColor: T.card,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: fieldBorder(T.line),
              enabledBorder: fieldBorder(T.line),
              focusedBorder: fieldBorder(T.accent, ancho: 1.5),
            ),
          ),
          if (!soloLectura) ...[
            const SizedBox(height: 12),
            _Filtros(seleccionado: filtro, onSelect: onFiltro, total: total),
          ],
        ],
      ),
    );
  }
}

class _Filtros extends StatelessWidget {
  const _Filtros(
      {required this.seleccionado, required this.onSelect, required this.total});

  final _Filtro seleccionado;
  final ValueChanged<_Filtro> onSelect;
  final int total;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pacientes = state.repo.pacientes(recolectorId: state.usuarioActual.id);

    var conBorrador = 0;
    var sinHoy = 0;
    for (final p in pacientes) {
      final eventos = state.repo.eventosDe(p.id);
      if (eventos.any((e) => !e.estado.esInmutable)) conBorrador++;
      if (!eventos.any((e) => F.diasEntre(Seed.hoy, e.fechaOcurrencia) == 0)) {
        sinHoy++;
      }
    }

    final etiquetas = {
      _Filtro.todos: 'Todos · $total',
      _Filtro.conBorrador: 'Con borrador · $conBorrador',
      _Filtro.sinRegistroHoy: 'Sin registro hoy · $sinHoy',
    };

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final entrada in etiquetas.entries)
          SelectablePill(
            texto: entrada.value,
            compacta: true,
            seleccionado: seleccionado == entrada.key,
            onTap: () => onSelect(entrada.key),
          ),
      ],
    );
  }
}

/// Recuento por rama. Dice cuántos hay en A y cuántos en B, y nada más: quien
/// lo mira no debe poder inferir cuál es cuál (CLAUDE.md §2).
class _ResumenRamas extends StatelessWidget {
  const _ResumenRamas();

  @override
  Widget build(BuildContext context) {
    final pacientes = AppScope.of(context).repo.pacientes();
    final enA = pacientes.where((p) => p.protocolo == Protocolo.a).length;

    Widget tarjeta(String titulo, int n, Color color) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(titulo, size: 10, color: T.faint),
                const SizedBox(height: 3),
                Text('$n',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w600, color: color)),
              ],
            ),
          ),
        );

    return Row(children: [
      tarjeta('Protocolo A', enA, T.ramaAFg),
      const SizedBox(width: 12),
      tarjeta('Protocolo B', pacientes.length - enA, T.ramaBFg),
    ]);
  }
}

/// Vista del recolector: primero lo que quedó a medias.
class _ListaCarga extends StatelessWidget {
  const _ListaCarga({required this.pacientes});

  final List<Patient> pacientes;

  @override
  Widget build(BuildContext context) {
    if (pacientes.isEmpty) {
      return const _Vacio('Ningún paciente coincide con el filtro.');
    }
    final repo = AppScope.of(context).repo;

    final abiertos = <Patient>[];
    final resto = <Patient>[];
    for (final p in pacientes) {
      if (repo.eventosDe(p.id).any((e) => !e.estado.esInmutable)) {
        abiertos.add(p);
      } else {
        resto.add(p);
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (abiertos.isNotEmpty) ...[
          const _TituloGrupo('Captura abierta'),
          for (final p in abiertos) _TarjetaCarga(paciente: p, urgente: true),
        ],
        if (resto.isNotEmpty) ...[
          const _TituloGrupo('En seguimiento'),
          for (final p in resto) _TarjetaCarga(paciente: p),
        ],
      ],
    );
  }
}

class _TarjetaCarga extends StatelessWidget {
  const _TarjetaCarga({required this.paciente, this.urgente = false});

  final Patient paciente;
  final bool urgente;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repo;
    final eventos = repo.eventosDe(paciente.id);
    final sinConsentimiento = !paciente.tieneConsentimiento;
    final ultimo = eventos.isEmpty ? null : eventos.last;
    final abierto = eventos.primeroQue((e) => !e.estado.esInmutable);

    final String linea;
    if (sinConsentimiento) {
      linea = 'Falta el consentimiento';
    } else if (abierto != null) {
      linea = '${abierto.referencia} · sin cerrar';
    } else if (ultimo != null) {
      linea = 'Último: ${ultimo.tipo.etiqueta} · '
          '${F.diaMes(ultimo.fechaOcurrencia)}';
    } else {
      linea = 'Sin eventos registrados';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: AppCard(
        acento: urgente ? T.warnDot : null,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => sinConsentimiento
              ? ConsentScreen(patientId: paciente.id)
              : PacienteTimelineScreen(patientId: paciente.id),
        )),
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
                      Text(paciente.nombre, style: T.title),
                      const SizedBox(height: 3),
                      Text('${paciente.codigo} · ${paciente.demografia}',
                          style: T.monoData),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // El evaluador de desenlaces no ve la rama: si la viera, su
                // juicio sobre el desenlace principal dejaría de ser
                // independiente (CLAUDE.md §2, BASES §4).
                if (AppScope.of(context).usuarioActual.veRamaAsignada)
                  ProtocolChip(paciente.protocolo),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: T.lineHair),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(linea, style: T.small)),
                if (sinConsentimiento)
                  const _EstadoTexto('Firmar', T.warnFg, T.warnDot)
                else if (abierto != null)
                  const _EstadoTexto('Borrador', T.warnFg, T.warnDot)
                else
                  _EstadoTexto(
                    ultimo?.sync == SyncStatus.sincronizado
                        ? 'Al día'
                        : 'En cola',
                    ultimo?.sync == SyncStatus.sincronizado ? T.okFg : T.warnFg,
                    ultimo?.sync == SyncStatus.sincronizado ? T.okDot : T.warnDot,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Vista del observador: una fila por paciente con el avance por fases.
class _ListaCohorte extends StatelessWidget {
  const _ListaCohorte({required this.pacientes});

  final List<Patient> pacientes;

  @override
  Widget build(BuildContext context) {
    if (pacientes.isEmpty) {
      return const _Vacio('Ningún paciente coincide con la búsqueda.');
    }
    final repo = AppScope.of(context).repo;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      children: [
        for (final p in pacientes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AppCard(
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
                            Text(p.codigo, style: T.title),
                            const SizedBox(height: 3),
                            Text(
                                '${p.institucion.codigo} · '
                                '${_recolector(p.recolectorId)}',
                                style: T.monoData),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (AppScope.of(context).usuarioActual.veRamaAsignada)
                        ProtocolChip(p.protocolo),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: T.lineHair),
                  const SizedBox(height: 8),
                  _AvancePorFases(eventos: repo.eventosDe(p.id)),
                ],
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: FasePillLegend(),
        ),
      ],
    );
  }

  static String _recolector(String id) => Seed.porId(id).nombre;
}

class _AvancePorFases extends StatelessWidget {
  const _AvancePorFases({required this.eventos});

  final List<EventoClinico> eventos;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final fase in FaseEstudio.values)
            FasePill(
              fase: fase,
              registrados: eventos
                  .where((e) => e.tipo.fase == fase && e.estado.esInmutable)
                  .length,
              enBorrador: eventos
                  .any((e) => e.tipo.fase == fase && !e.estado.esInmutable),
            ),
        ],
      );
}

class _TituloGrupo extends StatelessWidget {
  const _TituloGrupo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(T.gutter, 14, T.gutter, 6),
        child: SectionLabel(texto, color: T.faint),
      );
}

class _EstadoTexto extends StatelessWidget {
  const _EstadoTexto(this.texto, this.color, this.dot);

  final String texto;
  final Color color;
  final Color dot;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(texto,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
        ],
      );
}

class _Vacio extends StatelessWidget {
  const _Vacio(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(texto,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: T.faint)),
        ),
      );
}

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/collections.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/controls.dart';
import '../../data/local/seed_data.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/protocolo.dart';
import '../../domain/models/role.dart';
import '../../domain/models/visit.dart';
import '../consent/consent_screen.dart';
import '../enrollment/enrollment_screen.dart';
import '../visits/visit_capture_screen.dart';

/// 02 · Lista — recolector de campo · y · 03 · Lista — observador.
///
/// Una sola pantalla con dos caras, porque son la misma información leída con
/// permisos distintos: el recolector ve su carga del día y puede actuar; el
/// observador ve la cohorte entera y no puede tocar nada.
class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

enum _Filtro { todos, hoy, pendientes }

class _PatientListScreenState extends State<PatientListScreen> {
  _Filtro _filtro = _Filtro.todos;
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final usuario = state.usuarioActual;
    final soloLectura = usuario.role == Role.observador;

    final propios = state.repo.pacientes(
        recolectorId: usuario.role.veCohorteCompleta ? null : usuario.id);
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
      bottomNavigationBar: usuario.role.puedeEnrolar
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
        !p.numeroHistoriaClinica.contains(q)) {
      return false;
    }
    final visitas = state.repo.visitasDe(p.id);
    return switch (_filtro) {
      _Filtro.todos => true,
      _Filtro.hoy => visitas.any((v) =>
          F.diasEntre(Seed.hoy, v.fechaProgramada) == 0 && !v.status.esInmutable),
      _Filtro.pendientes => visitas.any((v) => v.status == VisitStatus.enCaptura),
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
                    Text('${usuario.nombre} · ${usuario.role.label}',
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
                            fontSize: 13, fontWeight: FontWeight.w600, color: T.body)),
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
                  : 'Buscar por nombre o núm. de historia',
              hintStyle: const TextStyle(fontSize: 14, color: T.faint),
              filled: true,
              fillColor: T.card,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

    var cuentaHoy = 0;
    var cuentaPend = 0;
    for (final p in pacientes) {
      final visitas = state.repo.visitasDe(p.id);
      if (visitas.any((v) =>
          F.diasEntre(Seed.hoy, v.fechaProgramada) == 0 && !v.status.esInmutable)) {
        cuentaHoy++;
      }
      if (visitas.any((v) => v.status == VisitStatus.enCaptura)) cuentaPend++;
    }

    final etiquetas = {
      _Filtro.todos: 'Todos · $total',
      _Filtro.hoy: 'Visita hoy · $cuentaHoy',
      _Filtro.pendientes: 'Pendientes · $cuentaPend',
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

class _ResumenRamas extends StatelessWidget {
  const _ResumenRamas();

  @override
  Widget build(BuildContext context) {
    final pacientes = AppScope.of(context).repo.pacientes();
    final vigente = pacientes.where((p) => p.protocolo == Protocolo.vigente).length;
    final nuevo = pacientes.length - vigente;

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
      tarjeta('Prot. vigente', vigente, T.vigenteFg),
      const SizedBox(width: 12),
      tarjeta('Prot. nuevo', nuevo, T.nuevoFg),
    ]);
  }
}

/// Vista del recolector: la carga del día primero, el seguimiento después.
class _ListaCarga extends StatelessWidget {
  const _ListaCarga({required this.pacientes});

  final List<Patient> pacientes;

  @override
  Widget build(BuildContext context) {
    if (pacientes.isEmpty) {
      return const _Vacio('Ningún paciente coincide con el filtro.');
    }
    final repo = AppScope.of(context).repo;

    final hoy = <(Patient, Visit)>[];
    final seguimiento = <(Patient, Visit?)>[];

    for (final p in pacientes) {
      final visitas = repo.visitasDe(p.id);
      final debida = visitas.primeroQue((v) =>
          !v.status.esInmutable && F.diasEntre(Seed.hoy, v.fechaProgramada) <= 0);
      if (debida != null) {
        hoy.add((p, debida));
      } else {
        seguimiento
            .add((p, visitas.primeroQue((v) => v.status == VisitStatus.programada)));
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (hoy.isNotEmpty) ...[
          const _TituloGrupo('Visita programada hoy'),
          for (final (p, v) in hoy)
            _TarjetaCarga(paciente: p, visita: v, urgente: true),
        ],
        if (seguimiento.isNotEmpty) ...[
          const _TituloGrupo('Seguimiento'),
          for (final (p, v) in seguimiento) _TarjetaCarga(paciente: p, visita: v),
        ],
      ],
    );
  }
}

class _TarjetaCarga extends StatelessWidget {
  const _TarjetaCarga(
      {required this.paciente, required this.visita, this.urgente = false});

  final Patient paciente;
  final Visit? visita;
  final bool urgente;

  @override
  Widget build(BuildContext context) {
    final v = visita;
    final sinConsentimiento = !paciente.tieneConsentimiento;

    final String linea;
    final Widget estado;
    if (v == null) {
      linea = 'Calendario completo';
      estado = const _EstadoTexto('Cerrado', T.okFg, T.okDot);
    } else if (urgente) {
      final enviado = v.sync == SyncStatus.sincronizado;
      linea = 'Día ${v.dia} · ${F.vencimiento(v.fechaProgramada, Seed.hoy)}';
      estado = _EstadoTexto(enviado ? 'Enviado' : 'Sin enviar',
          enviado ? T.okFg : T.warnFg, enviado ? T.okDot : T.warnDot);
    } else {
      linea = 'Próx. día ${v.dia} · ${F.diaMes(v.fechaProgramada)}';
      estado = const _EstadoTexto('Enviado', T.okFg, T.okDot);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: AppCard(
        acento: urgente ? T.warnDot : null,
        onTap: v == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => sinConsentimiento
                    ? ConsentScreen(patientId: paciente.id)
                    : VisitCaptureScreen(patientId: paciente.id, diaInicial: v.dia))),
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
                      Text(
                          'HC ${paciente.numeroHistoriaClinica} · ${paciente.demografia}',
                          style: T.monoData),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ProtocolChip(paciente.protocolo),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: T.lineHair),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                      sinConsentimiento ? 'Falta el consentimiento' : linea,
                      style: T.small),
                ),
                if (sinConsentimiento)
                  const _EstadoTexto('Firmar', T.warnFg, T.warnDot)
                else
                  estado,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Vista del observador: una fila por paciente con el progreso de las cinco
/// visitas. Sin acciones — el rol no puede modificar nada.
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
                            Text(p.nombre, style: T.title),
                            const SizedBox(height: 3),
                            Text(
                                'HC ${p.numeroHistoriaClinica} · recolecta: '
                                '${_recolector(p.recolectorId)}',
                                style: T.monoData),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      ProtocolChip(p.protocolo),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: T.lineHair),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final v in repo.visitasDe(p.id))
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: DayPill(dia: v.dia, status: v.status),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: DayPillLegend(),
        ),
      ],
    );
  }

  static String _recolector(String id) =>
      Seed.investigadores.firstWhere((i) => i.id == id).nombre;
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

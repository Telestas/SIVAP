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
import '../../domain/models/visit.dart';
import '../enrollment/enrollment_screen.dart';
import '../visits/visit_capture_screen.dart';

/// 07 · Administrador — escritorio, con auditoría.
///
/// La misma app, en pantalla ancha. El administrador ve la cohorte entera, el
/// estado de la cola de sincronización y el historial de correcciones.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String _seccion = 'Pacientes';
  String _busqueda = '';
  Protocolo? _filtroProtocolo;

  static const _secciones = [
    'Pacientes',
    'Visitas',
    'Consentimientos',
    'Auditoría',
    'Usuarios y roles',
    'Exportar datos',
  ];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pacientes = state.repo.pacientes().where((p) {
      if (_filtroProtocolo != null && p.protocolo != _filtroProtocolo) return false;
      final q = _busqueda.trim().toLowerCase();
      return q.isEmpty ||
          p.nombre.toLowerCase().contains(q) ||
          p.numeroHistoriaClinica.contains(q) ||
          p.carneIdentidad.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: T.surface,
      body: Row(
        children: [
          _BarraLateral(
            seleccionada: _seccion,
            secciones: _secciones,
            onSelect: (s) => setState(() => _seccion = s),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Cabecera(
                  onBuscar: (v) => setState(() => _busqueda = v),
                  filtroProtocolo: _filtroProtocolo,
                  onFiltroProtocolo: (p) => setState(() => _filtroProtocolo = p),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
                    children: [
                      _TablaPacientes(pacientes: pacientes),
                      const SizedBox(height: 18),
                      const _PanelAuditoria(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarraLateral extends StatelessWidget {
  const _BarraLateral(
      {required this.seleccionada, required this.secciones, required this.onSelect});

  final String seleccionada;
  final List<String> secciones;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Container(
      width: 220,
      color: T.sidebar,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SIVAP',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: T.onInk,
                        letterSpacing: 0.4)),
                SizedBox(height: 3),
                Text('PANEL DE ADMINISTRACIÓN',
                    style: TextStyle(
                        fontFamily: T.mono,
                        fontSize: 10,
                        letterSpacing: 0.9,
                        color: T.sidebarMuted)),
              ],
            ),
          ),
          for (final s in secciones)
            GestureDetector(
              onTap: () => onSelect(s),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                decoration: BoxDecoration(
                  color: s == seleccionada ? T.sidebarActive : null,
                  border: Border(
                    left: BorderSide(
                        color: s == seleccionada ? T.accent : Colors.transparent,
                        width: 3),
                  ),
                ),
                child: Text(s,
                    style: TextStyle(
                        fontSize: 14,
                        color: s == seleccionada ? T.onInk : T.sidebarText)),
              ),
            ),
          const Spacer(),
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: T.sidebarLine)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.usuarioActual.nombre,
                    style: const TextStyle(fontSize: 13, color: T.onInk)),
                const SizedBox(height: 3),
                Text(state.usuarioActual.role.label,
                    style: const TextStyle(
                        fontFamily: T.mono, fontSize: 10.5, color: T.sidebarMuted)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: state.cerrarSesion,
                  child: const Text('Cerrar sesión',
                      style: TextStyle(fontSize: 12.5, color: T.sidebarMuted)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.onBuscar,
    required this.filtroProtocolo,
    required this.onFiltroProtocolo,
  });

  final ValueChanged<String> onBuscar;
  final Protocolo? filtroProtocolo;
  final ValueChanged<Protocolo?> onFiltroProtocolo;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pacientes = state.repo.pacientes();
    final vigente = pacientes.where((p) => p.protocolo == Protocolo.vigente).length;

    return Container(
      decoration: const BoxDecoration(
        color: T.card,
        border: Border(bottom: BorderSide(color: T.lineFaint)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
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
                    const Text('Pacientes de la cohorte', style: T.h1),
                    const SizedBox(height: 4),
                    Text(
                        '${pacientes.length} enrolados · $vigente protocolo vigente · '
                        '${pacientes.length - vigente} protocolo nuevo',
                        style: const TextStyle(fontSize: 13, color: T.secondary)),
                  ],
                ),
              ),
              if (state.enCola > 0) ...[
                // Ancho fijo: dentro de un Row la banda no tiene restricción
                // horizontal propia y su `Expanded` interno no sabría medirse.
                SizedBox(
                  width: 290,
                  child: StatusBanner(
                    texto: '${state.enCola} registros en cola desde '
                        '${state.repo.dispositivosConCola} dispositivos',
                    accion: 'SINCRONIZAR',
                    onAccion: state.alternarConexion,
                  ),
                ),
                const SizedBox(width: 9),
              ],
              SizedBox(
                width: 140,
                child: AppButton('Exportar CSV',
                    primary: false, onTap: () => _avisoExportacion(context)),
              ),
              const SizedBox(width: 9),
              SizedBox(
                width: 120,
                child: AppButton('+ Enrolar',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const EnrollmentScreen()))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: onBuscar,
                  style: const TextStyle(fontSize: 13.5, color: T.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Buscar por nombre, HC o carné',
                    hintStyle: const TextStyle(fontSize: 13.5, color: T.faint),
                    filled: true,
                    fillColor: T.card,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    border: fieldBorder(T.line),
                    enabledBorder: fieldBorder(T.line),
                    focusedBorder: fieldBorder(T.accent, ancho: 1.5),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _FiltroProtocolo(valor: filtroProtocolo, onChanged: onFiltroProtocolo),
            ],
          ),
        ],
      ),
    );
  }

  static void _avisoExportacion(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      // La exportación real (.xlsx vía openpyxl) vive en el backend, que es
      // trabajo de un hito posterior. Decirlo es mejor que un botón que miente.
      content: Text(
          'La exportación se genera en el servidor (.xlsx). Pendiente del hito de backend.',
          style: TextStyle(fontSize: 13)),
      backgroundColor: T.ink,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

class _FiltroProtocolo extends StatelessWidget {
  const _FiltroProtocolo({required this.valor, required this.onChanged});

  final Protocolo? valor;
  final ValueChanged<Protocolo?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: T.card,
          border: Border.all(color: T.line),
          borderRadius: BorderRadius.circular(T.radiusField),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Protocolo?>(
            value: valor,
            isDense: true,
            borderRadius: BorderRadius.circular(T.radiusField),
            style: const TextStyle(fontSize: 13, color: T.body),
            dropdownColor: T.card,
            items: [
              const DropdownMenuItem(value: null, child: Text('Protocolo: todos')),
              for (final p in Protocolo.values)
                DropdownMenuItem(value: p, child: Text('Protocolo: ${p.rama}')),
            ],
            onChanged: onChanged,
          ),
        ),
      );
}

class _TablaPacientes extends StatelessWidget {
  const _TablaPacientes({required this.pacientes});

  final List<Patient> pacientes;

  static const _columnas = [2.0, 1.1, 1.2, 1.5, 1.2, 1.1, 0.9];
  static const _titulos = [
    'Paciente',
    'HC',
    'Protocolo',
    'Progreso de visitas',
    'Recolector',
    'Sincronización',
    'Auditoría'
  ];

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repo;

    return Container(
      decoration: BoxDecoration(
        color: T.card,
        border: Border.all(color: T.lineSoft),
        borderRadius: BorderRadius.circular(T.radiusPanel),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: T.subtle,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            child: Row(
              children: [
                for (var i = 0; i < _titulos.length; i++)
                  Expanded(
                    flex: (_columnas[i] * 10).round(),
                    child: SectionLabel(_titulos[i], size: 10),
                  ),
              ],
            ),
          ),
          if (pacientes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text('Ningún paciente coincide con el filtro.',
                  style: TextStyle(fontSize: 13.5, color: T.faint)),
            ),
          for (final p in pacientes)
            _FilaPaciente(paciente: p, visitas: repo.visitasDe(p.id)),
        ],
      ),
    );
  }
}

class _FilaPaciente extends StatelessWidget {
  const _FilaPaciente({required this.paciente, required this.visitas});

  final Patient paciente;
  final List<Visit> visitas;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repo;
    final correcciones = repo.auditoria().where((a) =>
        a.entidadId == paciente.id ||
        visitas.any((v) => v.id == a.entidadId)).length;

    final enCola = visitas.any((v) => v.sync != SyncStatus.sincronizado && !v.vacia);
    final primeraAbierta =
        visitas.primeroQue((v) => !v.status.esInmutable) ?? visitas.first;

    Widget celda(int flex, Widget hijo) =>
        Expanded(flex: (_TablaPacientes._columnas[flex] * 10).round(), child: hijo);

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VisitCaptureScreen(
              patientId: paciente.id, diaInicial: primeraAbierta.dia))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: T.lineHair)),
        ),
        child: Row(
          children: [
            celda(
              0,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(paciente.nombre,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: T.ink)),
                  const SizedBox(height: 2),
                  Text(paciente.demografia,
                      style: const TextStyle(fontSize: 11.5, color: T.faint)),
                ],
              ),
            ),
            celda(
                1,
                Text(paciente.numeroHistoriaClinica,
                    style: const TextStyle(
                        fontFamily: T.mono, fontSize: 12.5, color: T.body))),
            celda(2, Align(
                alignment: Alignment.centerLeft,
                child: ProtocolChip(paciente.protocolo))),
            celda(
              3,
              // Wrap y no Row: en una pantalla estrecha cinco píldoras no caben
              // en el ancho de la columna y un Row desborda.
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final v in visitas) DayPill(dia: v.dia, status: v.status),
                ],
              ),
            ),
            celda(
                4,
                Text(_recolector(paciente.recolectorId),
                    style: const TextStyle(fontSize: 13, color: T.body))),
            celda(
              5,
              Row(children: [
                SyncDot(enCola ? SyncStatus.enCola : SyncStatus.sincronizado),
                const SizedBox(width: 6),
                Text(enCola ? 'En cola' : 'Al día',
                    style: const TextStyle(fontSize: 12.5, color: T.body)),
              ]),
            ),
            celda(
              6,
              Text(
                  correcciones == 0
                      ? '—'
                      : '$correcciones ${correcciones == 1 ? 'corrección' : 'correcciones'}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: correcciones == 0 ? T.body : T.accent)),
            ),
          ],
        ),
      ),
    );
  }

  static String _recolector(String id) =>
      Seed.investigadores.firstWhere((i) => i.id == id).nombre;
}

/// Historial de auditoría. Es la prueba visible de que ninguna corrección
/// ocurrió en silencio.
class _PanelAuditoria extends StatelessWidget {
  const _PanelAuditoria();

  @override
  Widget build(BuildContext context) {
    final entradas = AppScope.of(context).repo.auditoria(limite: 6);

    return Container(
      decoration: BoxDecoration(
        color: T.card,
        border: Border.all(color: T.lineSoft),
        borderRadius: BorderRadius.circular(T.radiusPanel),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: T.lineHair)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Historial de auditoría — últimas correcciones',
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600, color: T.ink)),
                Text('Ver todo',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: T.accent)),
              ],
            ),
          ),
          for (final a in entradas)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF2F3F4))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 11,
                    child: Text(F.fechaHora(a.ocurridoEn),
                        style: const TextStyle(
                            fontFamily: T.mono, fontSize: 12, color: T.muted)),
                  ),
                  Expanded(
                    flex: 14,
                    child: Text(a.descripcionObjetivo,
                        style: const TextStyle(fontSize: 13, color: T.ink)),
                  ),
                  Expanded(
                    flex: 26,
                    child: _Cambio(
                        campo: a.campo,
                        anterior: a.valorAnterior,
                        nuevo: a.valorNuevo,
                        motivo: a.motivo),
                  ),
                  Expanded(
                    flex: 10,
                    child: Text(a.autorNombre,
                        style: const TextStyle(fontSize: 13, color: T.body)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Cambio extends StatelessWidget {
  const _Cambio(
      {required this.campo,
      required this.anterior,
      required this.nuevo,
      required this.motivo});

  final String campo;
  final String? anterior;
  final String? nuevo;
  final String motivo;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 13, color: T.body, height: 1.4),
          children: [
            TextSpan(text: '$campo: '),
            TextSpan(
                text: anterior ?? '—',
                style: const TextStyle(
                    fontFamily: T.mono,
                    decoration: TextDecoration.lineThrough,
                    color: T.dangerFg)),
            const TextSpan(text: ' → '),
            TextSpan(
                text: nuevo ?? '—',
                style: const TextStyle(
                    fontFamily: T.mono, fontWeight: FontWeight.w600, color: T.ink)),
            TextSpan(text: ' — $motivo'),
          ],
        ),
      );
}

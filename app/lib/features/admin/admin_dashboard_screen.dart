import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../sync/sincronizacion_screen.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/controls.dart';
import '../../data/local/seed_data.dart';
import '../../data/exportacion/descarga.dart';
import '../../data/exportacion/consentimiento_archivable.dart';
import '../../data/exportacion/xlsx_estudio.dart';
import '../../data/remoto/firestore_study_repository.dart';
import '../../domain/models/evento_clinico.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/protocolo.dart';
import '../../domain/models/role.dart';
import '../enrollment/enrollment_screen.dart';
import '../eventos/paciente_timeline_screen.dart';

/// Panel de administración, en escritorio.
///
/// Muestra la cohorte en A/B. El recuento por rama es solo un recuento: quien
/// lo mira no puede inferir cuál rama es cuál, porque el sistema no lo sabe
/// (CLAUDE.md §2).
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
    'Eventos',
    'Consentimientos',
    'Auditoría',
    'Usuarios y roles',
    'Exportar datos',
  ];

  @override
  Widget build(BuildContext context) {
    final movil = MediaQuery.sizeOf(context).width < 900;
    final state = AppScope.of(context);
    final pacientes = state.repo.pacientes().where((p) {
      if (_filtroProtocolo != null && p.protocolo != _filtroProtocolo) {
        return false;
      }
      final q = _busqueda.trim().toLowerCase();
      return q.isEmpty ||
          p.codigo.toLowerCase().contains(q) ||
          p.nombre.toLowerCase().contains(q) ||
          p.numeroHistoriaClinica.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: T.surface,
      drawer: movil
          ? Drawer(
              child: _BarraLateral(
                seleccionada: _seccion,
                secciones: _secciones,
                onSelect: (s) {
                  setState(() => _seccion = s);
                  Navigator.of(context).pop();
                },
              ),
            )
          : null,
      body: Row(
        children: [
          if (!movil)
            _BarraLateral(
              seleccionada: _seccion,
              secciones: _secciones,
              onSelect: (s) => setState(() => _seccion = s),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (movil)
                  Builder(
                      builder: (context) => Container(
                            color: T.sidebar,
                            child: SafeArea(
                                bottom: false,
                                child: Row(children: [
                                  IconButton(
                                    tooltip: 'Abrir secciones',
                                    icon:
                                        const Icon(Icons.menu, color: T.onInk),
                                    onPressed: () =>
                                        Scaffold.of(context).openDrawer(),
                                  ),
                                  Text(_seccion,
                                      style: const TextStyle(
                                          color: T.onInk,
                                          fontWeight: FontWeight.w600)),
                                ])),
                          )),
                _Cabecera(
                  seccion: _seccion,
                  onBuscar: (v) => setState(() => _busqueda = v),
                  filtroProtocolo: _filtroProtocolo,
                  onFiltroProtocolo: (p) =>
                      setState(() => _filtroProtocolo = p),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                        movil ? 16 : 28, 18, movil ? 16 : 28, 28),
                    children: [
                      ...switch (_seccion) {
                        'Eventos' => [_PanelEventos(pacientes: pacientes)],
                        'Consentimientos' => [
                            _PanelConsentimientos(pacientes: pacientes)
                          ],
                        'Auditoría' => const [_PanelAuditoria()],
                        'Usuarios y roles' => const [_PanelUsuarios()],
                        'Exportar datos' => const [_PanelExportacion()],
                        _ => [
                            _TablaPacientes(pacientes: pacientes),
                            const SizedBox(height: 18),
                            const _PanelAuditoria(limite: 6),
                          ],
                      },
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
      {required this.seleccionada,
      required this.secciones,
      required this.onSelect});

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
                Text('ENSAYO LIVERE',
                    style: TextStyle(
                        fontFamily: T.mono,
                        fontFamilyFallback: T.monoFallback,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                decoration: BoxDecoration(
                  color: s == seleccionada ? T.sidebarActive : null,
                  border: Border(
                    left: BorderSide(
                        color:
                            s == seleccionada ? T.accent : Colors.transparent,
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
                Text(state.usuarioActual.etiquetaRoles,
                    style: const TextStyle(
                        fontFamily: T.mono,
                        fontFamilyFallback: T.monoFallback,
                        fontSize: 10.5,
                        color: T.sidebarMuted)),
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
    required this.seccion,
    required this.onBuscar,
    required this.filtroProtocolo,
    required this.onFiltroProtocolo,
  });

  final String seccion;

  final ValueChanged<String> onBuscar;
  final Protocolo? filtroProtocolo;
  final ValueChanged<Protocolo?> onFiltroProtocolo;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pacientes = state.repo.pacientes();
    final enA = pacientes.where((p) => p.protocolo == Protocolo.a).length;
    final movil = MediaQuery.sizeOf(context).width < 700;

    return Container(
      decoration: const BoxDecoration(
        color: T.card,
        border: Border(bottom: BorderSide(color: T.lineFaint)),
      ),
      padding: EdgeInsets.fromLTRB(movil ? 16 : 28, 20, movil ? 16 : 28, 16),
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
                    Text(
                        seccion == 'Pacientes'
                            ? 'Pacientes del ensayo'
                            : seccion,
                        style: T.h1),
                    const SizedBox(height: 4),
                    Text(
                        seccion == 'Pacientes'
                            ? '${pacientes.length} enrolados · A: $enA · B: ${pacientes.length - enA}'
                            : _descripcionSeccion(seccion),
                        style:
                            const TextStyle(fontSize: 13, color: T.secondary)),
                  ],
                ),
              ),
              if (!movil && state.enCola > 0) ...[
                // Ancho fijo: dentro de un Row la banda no tiene restricción
                // horizontal propia y su `Expanded` interno no sabría medirse.
                SizedBox(
                  width: 290,
                  child: StatusBanner(
                    texto: '${state.enCola} registros en cola desde '
                        '${state.repo.dispositivosConCola} dispositivos',
                    accion: 'SINCRONIZAR',
                    onAccion: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SincronizacionScreen())),
                  ),
                ),
                const SizedBox(width: 9),
              ],
              if (!movil && seccion == 'Pacientes')
                SizedBox(
                  width: 140,
                  child: AppButton('Exportar',
                      primary: false, onTap: () => _avisoExportacion(context)),
                ),
              if (!movil) const SizedBox(width: 9),
              if (!movil && state.repo.admiteEscritura)
                SizedBox(
                  width: 120,
                  child: AppButton('+ Enrolar',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const EnrollmentScreen()))),
                ),
            ],
          ),
          if (movil &&
              (state.enCola > 0 ||
                  seccion == 'Pacientes' ||
                  state.repo.admiteEscritura)) ...[
            const SizedBox(height: 12),
            if (state.enCola > 0)
              StatusBanner(
                texto: '${state.enCola} registros en cola',
                accion: 'SINCRONIZAR',
                onAccion: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SincronizacionScreen())),
              ),
            if (state.enCola > 0) const SizedBox(height: 8),
            Row(children: [
              if (seccion == 'Pacientes')
                Expanded(
                    child: AppButton('Exportar',
                        primary: false,
                        onTap: () => _avisoExportacion(context))),
              if (seccion == 'Pacientes' && state.repo.admiteEscritura)
                const SizedBox(width: 8),
              if (state.repo.admiteEscritura)
                Expanded(
                    child: AppButton('+ Enrolar',
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const EnrollmentScreen())))),
            ]),
          ],
          if (seccion == 'Pacientes') ...[
            const SizedBox(height: 14),
            if (movil)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BuscadorPacientes(onBuscar: onBuscar),
                  const SizedBox(height: 8),
                  _FiltroProtocolo(
                      valor: filtroProtocolo, onChanged: onFiltroProtocolo),
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: _BuscadorPacientes(onBuscar: onBuscar)),
                  const SizedBox(width: 8),
                  _FiltroProtocolo(
                      valor: filtroProtocolo, onChanged: onFiltroProtocolo),
                ],
              ),
          ],
        ],
      ),
    );
  }

  static String _descripcionSeccion(String seccion) => switch (seccion) {
        'Eventos' =>
          'Hitos clínicos realmente registrados, sin calendario artificial.',
        'Consentimientos' =>
          'Control documental separado de los datos clínicos.',
        'Auditoría' => 'Historial completo de correcciones, autores y motivos.',
        'Usuarios y roles' => 'Perfiles aprovisionados para este centro.',
        'Exportar datos' =>
          'Identidad y dataset clínico se generan por separado.',
        _ => '',
      };

  static void _avisoExportacion(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:
          Text('Abra «Exportar datos» para descargar los libros separados.'),
      backgroundColor: T.ink,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

class _BuscadorPacientes extends StatelessWidget {
  const _BuscadorPacientes({required this.onBuscar});
  final ValueChanged<String> onBuscar;

  @override
  Widget build(BuildContext context) => TextField(
        onChanged: onBuscar,
        style: const TextStyle(fontSize: 13.5, color: T.ink),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Buscar por código, nombre o historia clínica',
          hintStyle: const TextStyle(fontSize: 13.5, color: T.faint),
          filled: true,
          fillColor: T.card,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          border: fieldBorder(T.line),
          enabledBorder: fieldBorder(T.line),
          focusedBorder: fieldBorder(T.accent, ancho: 1.5),
        ),
      );
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
              const DropdownMenuItem(
                  value: null, child: Text('Protocolo: todos')),
              for (final p in Protocolo.values)
                DropdownMenuItem(value: p, child: Text('Protocolo ${p.letra}')),
            ],
            onChanged: onChanged,
          ),
        ),
      );
}

class _TablaPacientes extends StatelessWidget {
  const _TablaPacientes({required this.pacientes});

  final List<Patient> pacientes;

  static const columnas = [2.0, 1.1, 1.0, 2.2, 1.2, 1.1, 0.9];
  static const _titulos = [
    'Paciente',
    'Centro',
    'Rama',
    'Avance por módulos',
    'Recolector',
    'Sincronización',
    'Auditoría'
  ];

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repo;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width < 900
            ? 900
            : MediaQuery.sizeOf(context).width - 290,
        child: Container(
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                child: Row(
                  children: [
                    for (var i = 0; i < _titulos.length; i++)
                      Expanded(
                        flex: (columnas[i] * 10).round(),
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
                _FilaPaciente(paciente: p, eventos: repo.eventosDe(p.id)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilaPaciente extends StatelessWidget {
  const _FilaPaciente({required this.paciente, required this.eventos});

  final Patient paciente;
  final List<EventoClinico> eventos;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repo;
    final ids = eventos.map((e) => e.id).toSet();
    final correcciones =
        repo.auditoria().where((a) => ids.contains(a.entidadId)).length;
    final enCola =
        eventos.any((e) => e.sync != SyncStatus.sincronizado && !e.vacio);

    Widget celda(int indice, Widget hijo) => Expanded(
        flex: (_TablaPacientes.columnas[indice] * 10).round(), child: hijo);

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PacienteTimelineScreen(patientId: paciente.id))),
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
                  Text(paciente.codigo,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: T.ink)),
                  const SizedBox(height: 2),
                  Text('${paciente.demografia} · ${paciente.nombre}',
                      style: const TextStyle(fontSize: 11.5, color: T.faint)),
                ],
              ),
            ),
            celda(
                1,
                Text(paciente.institucion.codigo,
                    style: const TextStyle(
                        fontFamily: T.mono,
                        fontFamilyFallback: T.monoFallback,
                        fontSize: 12.5,
                        color: T.body))),
            celda(
                2,
                Align(
                    alignment: Alignment.centerLeft,
                    child: ProtocolChip(paciente.protocolo))),
            celda(
              3,
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final fase in FaseEstudio.values)
                    FasePill(
                      fase: fase,
                      registrados: eventos
                          .where((e) =>
                              e.tipo.fase == fase && e.estado.esInmutable)
                          .length,
                      enBorrador: eventos.any(
                          (e) => e.tipo.fase == fase && !e.estado.esInmutable),
                    ),
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
                const SizedBox(width: 4),
                Flexible(
                    child: Text(enCola ? 'En cola' : 'Al día',
                        style: const TextStyle(fontSize: 12.5, color: T.body))),
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

  static String _recolector(String id) {
    try {
      return Seed.porId(id).nombre;
    } on StateError {
      // Los perfiles reales no se incorporan al binario. Las reglas solo
      // permiten leerlos a quien los administra.
      return 'Investigador del estudio';
    }
  }
}

class _PanelEventos extends StatelessWidget {
  const _PanelEventos({required this.pacientes});

  final List<Patient> pacientes;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repo;
    final eventos = [
      for (final paciente in pacientes)
        for (final evento in repo.eventosDe(paciente.id))
          (paciente: paciente, evento: evento),
    ]..sort(
        (a, b) => b.evento.fechaOcurrencia.compareTo(a.evento.fechaOcurrencia));
    return _PanelListado(
      titulo: '${eventos.length} eventos registrados',
      vacio: 'Todavía no hay eventos clínicos registrados.',
      filas: [
        for (final item in eventos)
          _FilaResumen(
            principal: item.evento.referencia,
            secundario:
                '${item.paciente.codigo} · ${item.evento.institucion.codigo}',
            derecha:
                '${F.fechaHora(item.evento.fechaOcurrencia)} · ${item.evento.estado.etiqueta}',
          ),
      ],
    );
  }
}

class _PanelConsentimientos extends StatelessWidget {
  const _PanelConsentimientos({required this.pacientes});

  final List<Patient> pacientes;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final firmados = pacientes.where((p) => p.tieneConsentimiento).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _PanelListado(
        titulo: '$firmados de ${pacientes.length} consentimientos registrados',
        vacio: 'Todavía no hay pacientes enrolados.',
        filas: [
          for (final paciente in pacientes)
            _FilaResumen(
              principal: paciente.codigo,
              secundario: paciente.institucion.codigo,
              derecha: paciente.tieneConsentimiento
                  ? 'REGISTRADO · ${paciente.consentimientoId}'
                  : 'PENDIENTE',
            ),
        ],
      ),
      for (final paciente in pacientes)
        if (paciente.consentimientoId case final id?)
          if (state.repo.consentimiento(id) case final consentimiento?)
            TextButton.icon(
              onPressed: () async {
                try {
                  if (state.repo is FirestoreStudyRepository) {
                    await (state.repo as FirestoreStudyRepository)
                        .registrarArchivoConsentimiento(id);
                  }
                  descargarArchivo(
                    'consentimiento-${paciente.codigo}-$id.html',
                    utf8.encode(consentimientoArchivable(
                        consentimiento, paciente.codigo)),
                    'text/html;charset=utf-8',
                  );
                } on Object catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('No se pudo archivar: $error'),
                    ));
                  }
                }
              },
              icon: const Icon(Icons.download),
              label: Text('Archivar consentimiento ${paciente.codigo}'),
            ),
    ]);
  }
}

class _PanelUsuarios extends StatefulWidget {
  const _PanelUsuarios();

  @override
  State<_PanelUsuarios> createState() => _PanelUsuariosState();
}

class _PanelUsuariosState extends State<_PanelUsuarios> {
  bool _ocupado = false;

  Future<void> _aprobar(QueryDocumentSnapshot<Map<String, dynamic>> solicitud,
      Rol rol, String codigoCentro) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      final datos = solicitud.data();
      if (datos['institucion_codigo'] != codigoCentro ||
          datos['estado'] != 'pendiente' ||
          rol == Rol.investigadorPrincipal) {
        throw StateError('La solicitud o la función no son aprobables.');
      }
      final db = FirebaseFirestore.instance;
      final lote = db.batch();
      final ahora = FieldValue.serverTimestamp();
      final aprobador = AppScope.read(context).usuarioActual.id;
      lote.set(db.collection('investigadores').doc(solicitud.id), {
        'nombre': datos['nombre'],
        'correo': datos['correo'],
        'institucion_codigo': codigoCentro,
        'roles': [rol.name],
        'aprobado_por': aprobador,
        'aprobado_en': ahora,
      });
      lote.update(solicitud.reference, {
        'estado': 'aprobado',
        'rol_aprobado': rol.name,
        'aprobado_por': aprobador,
        'aprobado_en': ahora,
      });
      await lote.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Acceso aprobado. La persona ya puede iniciar sesión.')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo aprobar la solicitud: $error')));
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _elegirRol(QueryDocumentSnapshot<Map<String, dynamic>> solicitud,
      String codigoCentro) async {
    final rol = await showDialog<Rol>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Aprobar a ${solicitud.data()['nombre']}'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text('El rol de Investigador principal se asigna mediante '
                'aprovisionamiento administrativo en Firebase.'),
          ),
          for (final opcion in Rol.values)
            if (opcion != Rol.investigadorPrincipal)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, opcion),
                child: Text(opcion.etiqueta),
              ),
        ],
      ),
    );
    if (rol != null && mounted) await _aprobar(solicitud, rol, codigoCentro);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final usuarios = state.repo.investigadores();
    final visibles = usuarios.isEmpty ? [state.usuarioActual] : usuarios;
    final listado = _PanelListado(
      titulo: '${visibles.length} perfiles del centro',
      vacio: 'No hay perfiles visibles.',
      pie: 'Los roles existentes no se cambian desde este panel.',
      filas: [
        for (final usuario in visibles)
          _FilaResumen(
            principal: usuario.nombre,
            secundario: usuario.usuario,
            derecha: usuario.etiquetaRoles,
          ),
      ],
    );
    if (!state.usuarioActual.puedeGestionarUsuarios ||
        !state.requiereAutenticacionRemota) {
      return listado;
    }
    final codigo = state.usuarioActual.institucion.codigo;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('solicitudes_acceso')
            .where('institucion_codigo', isEqualTo: codigo)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
                'No se pudieron cargar las solicitudes: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final pendientes = snapshot.data!.docs
              .where((d) => d.data()['estado'] == 'pendiente')
              .toList();
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Solicitudes pendientes: ${pendientes.length}',
                    style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                for (final solicitud in pendientes)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${solicitud.data()['nombre']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${solicitud.data()['correo']}'),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: _ocupado
                                  ? null
                                  : () => _elegirRol(solicitud, codigo),
                              child: const Text('Aprobar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
              ]);
        },
      ),
      listado,
    ]);
  }
}

class _PanelExportacion extends StatelessWidget {
  const _PanelExportacion();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final autor = state.usuario;
    if (autor == null) return const SizedBox.shrink();
    final clinico = autor.puedeExportar && autor.veRamaAsignada;
    final identidad = autor.roles.contains(Rol.investigadorPrincipal);
    final fecha = DateTime.now().toIso8601String().substring(0, 10);
    Future<void> entregar(String nombre, List<int> bytes) async {
      try {
        if (state.repo is FirestoreStudyRepository) {
          await (state.repo as FirestoreStudyRepository)
              .registrarExportacion(nombre);
        }
        descargarArchivo(
          nombre,
          bytes,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo registrar la exportación: $error'),
          ));
        }
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Archivos del centro', style: TextStyle(fontSize: 20)),
      const SizedBox(height: 12),
      const Text(
          'Cada descarga contiene solo los registros visibles de este centro. '
          'Custodie la ficha de identidad por separado.'),
      const SizedBox(height: 16),
      if (clinico)
        FilledButton.icon(
          onPressed: () => entregar(
            'sivap-clinico-$fecha.xlsx',
            XlsxEstudio.clinico(state.repo, autor),
          ),
          icon: const Icon(Icons.download),
          label: const Text('Descargar dataset clínico'),
        ),
      if (identidad) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => entregar(
            'sivap-identidad-$fecha.xlsx',
            XlsxEstudio.identidad(state.repo, autor),
          ),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Descargar ficha de identidad'),
        ),
      ],
      if (!clinico && !identidad)
        const Text('Su función no permite exportar estos archivos.'),
    ]);
  }
}

class _PanelListado extends StatelessWidget {
  const _PanelListado({
    required this.titulo,
    required this.vacio,
    required this.filas,
    this.pie,
  });

  final String titulo;
  final String vacio;
  final List<Widget> filas;
  final String? pie;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: T.card,
          border: Border.all(color: T.lineSoft),
          borderRadius: BorderRadius.circular(T.radiusPanel),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Text(titulo,
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: T.ink)),
            ),
            if (filas.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(vacio,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: T.faint)),
              )
            else
              ...filas,
            if (pie != null)
              Container(
                color: T.subtle,
                padding: const EdgeInsets.all(14),
                child: Text(pie!,
                    style: const TextStyle(
                        fontSize: 12.5, color: T.secondary, height: 1.45)),
              ),
          ],
        ),
      );
}

class _FilaResumen extends StatelessWidget {
  const _FilaResumen({
    required this.principal,
    required this.secundario,
    required this.derecha,
  });

  final String principal;
  final String secundario;
  final String derecha;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: T.lineHair)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(principal,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: T.ink)),
                  const SizedBox(height: 3),
                  Text(secundario,
                      style: const TextStyle(fontSize: 12, color: T.faint)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
                child: Text(derecha,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontFamily: T.mono,
                        fontFamilyFallback: T.monoFallback,
                        fontSize: 11.5,
                        color: T.body))),
          ],
        ),
      );
}

/// Historial de auditoría. Es la prueba visible de que ninguna corrección
/// ocurrió en silencio.
class _PanelAuditoria extends StatelessWidget {
  const _PanelAuditoria({this.limite});

  final int? limite;

  @override
  Widget build(BuildContext context) {
    final entradas = AppScope.of(context).repo.auditoria(limite: limite);

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
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                    limite == null
                        ? 'Historial completo de auditoría'
                        : 'Historial de auditoría — últimas correcciones',
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: T.ink)),
                if (limite != null)
                  const Text('Ver todo',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: T.accent)),
              ],
            ),
          ),
          if (entradas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Sin correcciones registradas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: T.faint)),
            ),
          for (final a in entradas)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF2F3F4))),
              ),
              child: MediaQuery.sizeOf(context).width < 900
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(F.fechaHora(a.ocurridoEn),
                            style:
                                const TextStyle(fontSize: 12, color: T.muted)),
                        const SizedBox(height: 4),
                        Text(a.descripcionObjetivo),
                        _Cambio(
                            campo: a.campo,
                            anterior: a.valorAnterior,
                            nuevo: a.valorNuevo,
                            motivo: a.motivo),
                        Text(a.autorNombre),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          flex: 11,
                          child: Text(F.fechaHora(a.ocurridoEn),
                              style: const TextStyle(
                                  fontFamily: T.mono,
                                  fontFamilyFallback: T.monoFallback,
                                  fontSize: 12,
                                  color: T.muted)),
                        ),
                        Expanded(
                          flex: 16,
                          child: Text(a.descripcionObjetivo,
                              style:
                                  const TextStyle(fontSize: 13, color: T.ink)),
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
                              style:
                                  const TextStyle(fontSize: 13, color: T.body)),
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
  const _Cambio({
    required this.campo,
    required this.anterior,
    required this.nuevo,
    required this.motivo,
  });

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
                    fontFamilyFallback: T.monoFallback,
                    decoration: TextDecoration.lineThrough,
                    color: T.dangerFg)),
            const TextSpan(text: ' → '),
            TextSpan(
                text: nuevo ?? '—',
                style: const TextStyle(
                    fontFamily: T.mono,
                    fontFamilyFallback: T.monoFallback,
                    fontWeight: FontWeight.w600,
                    color: T.ink)),
            TextSpan(text: ' — $motivo'),
          ],
        ),
      );
}

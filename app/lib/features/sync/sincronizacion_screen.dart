import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/controls.dart';

/// Qué falta por enviar, y qué pasó con lo que se envió.
///
/// Existe porque «se envió» y «llegó» no son lo mismo, y con esta conectividad
/// la diferencia se nota. Aquí se ve cuánto espera, se manda, y —lo que más
/// importa— **se lee por qué el servidor no admitió algo**. Un registro
/// rechazado sin motivo a la vista es un registro que se pierde sin que nadie
/// se entere.
class SincronizacionScreen extends StatefulWidget {
  const SincronizacionScreen({super.key});

  @override
  State<SincronizacionScreen> createState() => _SincronizacionScreenState();
}

class _SincronizacionScreenState extends State<SincronizacionScreen> {
  final _servidor = TextEditingController();
  final _usuario = TextEditingController();
  final _contrasena = TextEditingController();
  String? _aviso;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_servidor.text.isEmpty) {
      _servidor.text = AppScope.of(context).sincronizacion.servidor?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_servidor, _usuario, _contrasena]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _entrar() async {
    final sync = AppScope.read(context).sincronizacion;
    sync.configurar(_servidor.text);
    final error = await sync.entrar(_usuario.text.trim(), _contrasena.text);
    if (!mounted) return;
    setState(() {
      _aviso = error;
      if (error == null) _contrasena.clear();
    });
  }

  Future<void> _sincronizar() async {
    final sync = AppScope.read(context).sincronizacion;
    final resultado = await sync.sincronizar();
    if (!mounted) return;
    setState(() => _aviso = resultado.mensaje);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final sync = state.sincronizacion;

    return Scaffold(
      backgroundColor: T.surface,
      appBar: AppTopBar(
        titulo: 'Sincronización',
        trailing: MetaChip(state.textoSyncCorto,
            tono: state.hayCola ? MetaTone.aviso : MetaTone.ok),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(T.gutter, 16, T.gutter, 16),
          children: [
            // Lo primero, y a propósito: que quede claro que no enviar no
            // impide trabajar (CLAUDE.md §12).
            StatusBanner(
              texto: state.hayCola
                  ? '${state.textoSync}. Se puede seguir capturando sin '
                      'conexión: lo pendiente no se pierde.'
                  : 'No hay nada esperando a salir de este aparato.',
              alineaArriba: true,
            ),

            const SizedBox(height: 20),
            const SectionLabel('Servidor'),
            const SizedBox(height: 8),
            LabeledField(
                label: 'Dirección', controller: _servidor, mono: true),
            const SizedBox(height: 8),
            Text(
              'Este aparato se identifica como ${sync.dispositivoId}. '
              'El identificador se guarda: si cambiara en cada arranque, el '
              'servidor le daría un tramo nuevo de la secuencia cada vez.',
              style: T.small,
            ),

            const SizedBox(height: 20),
            const SectionLabel('Acceso al servidor'),
            const SizedBox(height: 4),
            const Text(
              'No es el acceso a la app: eso funciona sin conexión. Esto solo '
              'autoriza el envío.',
              style: T.small,
            ),
            const SizedBox(height: 10),
            if (sync.sesion case final abierta?)
              _Sesion(
                nombre: abierta.nombre,
                roles: abierta.roles.join(' · '),
                onSalir: () {
                  sync.salir();
                  setState(() => _aviso = null);
                },
              )
            else ...[
              LabeledField(label: 'Usuario', controller: _usuario),
              const SizedBox(height: 12),
              LabeledField(
                  label: 'Contraseña', controller: _contrasena, oculto: true),
              const SizedBox(height: 12),
              AppButton('Entrar',
                  primary: false,
                  enabled: !sync.enCurso && _servidor.text.trim().isNotEmpty,
                  onTap: _entrar),
            ],

            if (_aviso != null) ...[
              const SizedBox(height: 16),
              StatusBanner(texto: _aviso!, alineaArriba: true),
            ],

            if (sync.rechazos.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(children: [
                const SectionLabel('No entraron'),
                const SizedBox(width: 8),
                MetaChip('${sync.rechazos.length}', tono: MetaTone.aviso),
              ]),
              const SizedBox(height: 4),
              const Text(
                'Siguen guardados en el aparato y volverán a intentarlo. '
                'Entran solos en cuanto el motivo desaparezca.',
                style: T.small,
              ),
              const SizedBox(height: 10),
              for (final r in sync.rechazos) ...[
                _Rechazo(tipo: r.tipo, motivo: r.motivo),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomActions(children: [
        Expanded(
          child: AppButton(
            sync.enCurso ? 'Enviando…' : 'Enviar lo pendiente',
            enabled: !sync.enCurso && sync.haySesion && state.hayCola,
            onTap: _sincronizar,
          ),
        ),
      ]),
    );
  }
}

class _Sesion extends StatelessWidget {
  const _Sesion(
      {required this.nombre, required this.roles, required this.onSalir});

  final String nombre;
  final String roles;
  final VoidCallback onSalir;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombre, style: T.title),
                  const SizedBox(height: 2),
                  Text(roles, style: T.small),
                ],
              ),
            ),
            GestureDetector(
              onTap: onSalir,
              behavior: HitTestBehavior.opaque,
              child: const MetaChip('SALIR'),
            ),
          ],
        ),
      );
}

class _Rechazo extends StatelessWidget {
  const _Rechazo({required this.tipo, required this.motivo});

  final String tipo;
  final String motivo;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MetaChip(tipo.toUpperCase(), tono: MetaTone.aviso),
            const SizedBox(height: 6),
            // El mensaje del servidor tal cual. Resumirlo aquí sería quitarle
            // a quien lo lea lo único que le dice qué arreglar.
            Text(motivo, style: T.bodyText),
          ],
        ),
      );
}

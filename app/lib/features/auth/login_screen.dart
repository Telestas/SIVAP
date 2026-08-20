import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/controls.dart';
import '../../domain/models/role.dart';
import '../../data/local/seed_data.dart';

/// 01 · Acceso y rol.
///
/// En el MVP el rol se elige al entrar para poder demostrar las tres vistas.
/// En producción el rol viene del servidor con la credencial y este selector
/// desaparece: un investigador no decide sus propios permisos.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usuario = TextEditingController(text: 'dra.morales');
  final _clave = TextEditingController(text: '········');
  Role _role = Role.recolector;

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  void _entrar() {
    final state = AppScope.read(context);
    final investigador = Seed.investigadores.firstWhere((i) => i.role == _role);
    state.iniciarSesion(investigador);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final config = state.repo.config;

    return Scaffold(
      backgroundColor: T.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
          children: [
            const Text('SIVAP',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: T.ink)),
            const SizedBox(height: 6),
            Text('${config.nombreEstudio}\n${config.centro} · ${config.servicio}',
                style: const TextStyle(fontSize: 13, color: T.secondary, height: 1.5)),
            const SizedBox(height: 22),

            if (state.sinConexion)
              StatusBanner(
                texto: 'Sin conexión de datos. Se validará su credencial guardada '
                    'en el dispositivo; los envíos quedarán en cola.',
                alineaArriba: true,
                accion: 'CAMBIAR',
                onAccion: state.alternarConexion,
              )
            else
              StatusBanner(
                texto: 'Conectado. La credencial se validará contra el servidor.',
                tono: BannerTone.ok,
                accion: 'CAMBIAR',
                onAccion: state.alternarConexion,
              ),

            // Qué garantiza el almacén de esta compilación. Si no cifra o no
            // persiste, se dice aquí y no en letra pequeña.
            if (state.almacen.advertencia != null) ...[
              const SizedBox(height: 12),
              StatusBanner(
                  texto: state.almacen.advertencia!, alineaArriba: true),
            ],

            // El CEI aún no ha aprobado: la app funciona, pero no con pacientes
            // reales. Decirlo aquí y no en letra pequeña es deliberado.
            if (!config.consentimientoAprobadoPorCei) ...[
              const SizedBox(height: 12),
              const StatusBanner(
                texto: 'Modo demostración. El CEI no ha aprobado aún protocolo y '
                    'consentimiento: no se admite el enrolamiento de pacientes reales.',
                alineaArriba: true,
              ),
            ],

            const SizedBox(height: 22),
            LabeledField(label: 'Usuario', controller: _usuario),
            const SizedBox(height: 14),
            LabeledField(label: 'Contraseña', controller: _clave),

            const SizedBox(height: 22),
            const SectionLabel('Rol de sesión'),
            const SizedBox(height: 9),
            for (final role in Role.values) ...[
              _OpcionRol(
                role: role,
                seleccionado: _role == role,
                onTap: () => setState(() => _role = role),
              ),
              if (role != Role.values.last) const SizedBox(height: 8),
            ],

            const SizedBox(height: 28),
            AppButton('Entrar', onTap: _entrar),
            const SizedBox(height: 12),
            Text('v1.0.4 · última sincronización 19 ago, 17:22',
                textAlign: TextAlign.center,
                style: T.label(size: 10.5, color: T.faint, tracking: 0.05)),
          ],
        ),
      ),
    );
  }
}

class _OpcionRol extends StatelessWidget {
  const _OpcionRol(
      {required this.role, required this.seleccionado, required this.onTap});

  final Role role;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        inMutuallyExclusiveGroup: true,
        selected: seleccionado,
        label: role.label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: seleccionado ? T.accentTint : T.card,
              border: Border.all(
                  color: seleccionado ? T.accent : T.line,
                  width: seleccionado ? 1.5 : 1),
              borderRadius: BorderRadius.circular(T.radiusCard),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 15,
                  height: 15,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: T.card,
                    border: Border.all(
                        color: seleccionado ? T.accent : T.disabled,
                        width: seleccionado ? 4.5 : 1.5),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(role.label,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600, color: T.ink)),
                      const SizedBox(height: 2),
                      Text(role.description,
                          style: const TextStyle(
                              fontSize: 12, color: T.secondary, height: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

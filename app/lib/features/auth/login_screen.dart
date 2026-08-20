import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/controls.dart';
import '../../data/local/seed_data.dart';
import '../../domain/models/role.dart';

/// Acceso al sistema.
///
/// En el MVP se elige con qué función entrar, para poder recorrer la app con
/// cada una y comprobar qué ve y qué no. **En producción la función viene del
/// servidor con la credencial**: un investigador no elige sus propios permisos,
/// y menos en un ensayo donde los permisos son la separación de funciones que
/// sostiene el cegamiento.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usuario = TextEditingController();
  final _clave = TextEditingController(text: '········');
  Investigador _seleccionado = Seed.investigadores.first;

  @override
  void initState() {
    super.initState();
    _usuario.text = _seleccionado.usuario;
  }

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  void _elegir(Investigador i) => setState(() {
        _seleccionado = i;
        _usuario.text = i.usuario;
      });

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
            Text('Ensayo ${config.acronimo}\n${config.nombreEstudio}',
                style: const TextStyle(
                    fontSize: 13, color: T.secondary, height: 1.5)),
            const SizedBox(height: 22),

            if (state.sinConexion)
              StatusBanner(
                texto: 'Sin conexión de datos. Se validará su credencial '
                    'guardada en el dispositivo; los envíos quedarán en cola.',
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
              StatusBanner(texto: state.almacen.advertencia!, alineaArriba: true),
            ],

            // El CEI aún no ha aprobado: la app funciona, pero no con pacientes
            // reales. Decirlo aquí y no en letra pequeña es deliberado.
            if (!config.consentimientoAprobadoPorCei) ...[
              const SizedBox(height: 12),
              const StatusBanner(
                texto: 'Modo demostración. El CEI no ha aprobado aún protocolo '
                    'y consentimiento: no se admite el enrolamiento de '
                    'pacientes reales.',
                alineaArriba: true,
              ),
            ],

            const SizedBox(height: 22),
            LabeledField(label: 'Usuario', controller: _usuario, readOnly: true),
            const SizedBox(height: 14),
            LabeledField(label: 'Contraseña', controller: _clave),

            const SizedBox(height: 22),
            const SectionLabel('Función en el ensayo'),
            const SizedBox(height: 6),
            const Text(
                'El diseño del ensayo separa funciones por razones '
                'metodológicas: quien selecciona pacientes está cegado a la '
                'secuencia, y quien evalúa desenlaces, a la rama asignada.',
                style: TextStyle(fontSize: 12, color: T.secondary, height: 1.45)),
            const SizedBox(height: 12),
            for (final i in Seed.investigadores) ...[
              _OpcionFuncion(
                investigador: i,
                seleccionado: _seleccionado.id == i.id,
                onTap: () => _elegir(i),
              ),
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 20),
            AppButton('Entrar',
                onTap: () => AppScope.read(context).iniciarSesion(_seleccionado)),
            const SizedBox(height: 12),
            Text('v0.2 · ${config.definicionFormulario.version}',
                textAlign: TextAlign.center,
                style: T.label(size: 10.5, color: T.faint, tracking: 0.05)),
          ],
        ),
      ),
    );
  }
}

class _OpcionFuncion extends StatelessWidget {
  const _OpcionFuncion({
    required this.investigador,
    required this.seleccionado,
    required this.onTap,
  });

  final Investigador investigador;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        inMutuallyExclusiveGroup: true,
        selected: seleccionado,
        label: investigador.etiquetaRoles,
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(investigador.etiquetaRoles,
                                style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: T.ink)),
                          ),
                          const SizedBox(width: 8),
                          MetaChip(investigador.institucion.codigo),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(investigador.rolPrincipal.descripcion,
                          style: const TextStyle(
                              fontSize: 12, color: T.secondary, height: 1.45)),
                      if (seleccionado) ...[
                        const SizedBox(height: 6),
                        Text('Cegado a: ${investigador.rolPrincipal.cegadoA}',
                            style: T.label(
                                size: 10.5, color: T.body, tracking: 0.02)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

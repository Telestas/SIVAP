import 'package:flutter/material.dart';

import '../sync/sincronizacion_screen.dart';
import 'solicitar_acceso_screen.dart';
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
  final _clave = TextEditingController();
  Investigador _seleccionado = Seed.investigadores.first;
  String? _error;
  bool _entrando = false;
  bool _recuperando = false;

  @override
  void initState() {
    super.initState();
    // Teclear un usuario selecciona su función, y elegir función rellena el
    // usuario. Los dos controles miran lo mismo y tienen que ir a la par.
    _usuario.addListener(_sincronizarDesdeUsuario);
  }

  @override
  void dispose() {
    _usuario
      ..removeListener(_sincronizarDesdeUsuario)
      ..dispose();
    _clave.dispose();
    super.dispose();
  }

  void _sincronizarDesdeUsuario() {
    final encontrado = _buscar(_usuario.text);
    setState(() {
      if (encontrado != null) _seleccionado = encontrado;
      _error = null;
    });
  }

  Investigador? _buscar(String usuario) {
    final u = usuario.trim().toLowerCase();
    for (final i in Seed.investigadores) {
      if (i.usuario.toLowerCase() == u) return i;
    }
    return null;
  }

  void _elegir(Investigador i) => setState(() {
        _seleccionado = i;
        _error = null;
        if (_usuario.text != i.usuario) _usuario.text = i.usuario;
      });

  Future<void> _entrar() async {
    final state = AppScope.read(context);
    if (state.requiereAutenticacionRemota) {
      if (_usuario.text.trim().isEmpty || _clave.text.isEmpty) {
        setState(() => _error = 'Escriba el correo y la contraseña.');
        return;
      }
      setState(() {
        _entrando = true;
        _error = null;
      });
      try {
        await state.iniciarSesionRemota(
          _usuario.text.trim(),
          _clave.text,
        );
      } on Object catch (error) {
        if (!mounted) return;
        setState(() => _error = _mensajeDe(error));
      } finally {
        if (mounted) setState(() => _entrando = false);
      }
      return;
    }

    final encontrado = _buscar(_usuario.text);
    if (encontrado == null) {
      setState(() => _error =
          'No hay ningún investigador con el usuario «${_usuario.text.trim()}». '
              'Elija una función de la lista o escriba uno de los usuarios que '
              'aparecen en ella.');
      return;
    }
    if (_clave.text.isEmpty) {
      setState(() => _error = 'Escriba la contraseña.');
      return;
    }
    state.iniciarSesion(encontrado);
  }

  Future<void> _recuperarAcceso() async {
    final correo = _usuario.text.trim();
    if (correo.isEmpty) {
      setState(() => _error = 'Escriba primero su correo.');
      return;
    }
    setState(() {
      _recuperando = true;
      _error = null;
    });
    try {
      await AppScope.read(context).recuperarAcceso(correo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Solicitud enviada. Revise Recibidos, Spam y Promociones. El remitente puede aparecer como SIVAP o Firebase.',
        ),
        behavior: SnackBarBehavior.floating,
      ));
    } on Object catch (error) {
      if (mounted) setState(() => _error = _mensajeDe(error));
    } finally {
      if (mounted) setState(() => _recuperando = false);
    }
  }

  static String _mensajeDe(Object error) {
    final mensaje = error.toString();
    if (mensaje.startsWith('Exception: ')) {
      return mensaje.substring('Exception: '.length);
    }
    if (mensaje.contains('permission-denied')) {
      return 'La cuenta no tiene permiso para leer los datos del estudio.';
    }
    return mensaje;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final config = state.repo.config;
    final remoto = state.requiereAutenticacionRemota;

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

            // Entrar aquí no habla con el servidor, y conviene decirlo: la
            // app trabaja sin conexión y el envío es otra cosa (CLAUDE.md §12).
            StatusBanner(
              texto: remoto
                  ? 'La cuenta y las funciones las valida Firebase. La captura '
                      'móvil sigue disponible sin conexión tras iniciar sesión.'
                  : 'El acceso a la app no necesita conexión. El envío al '
                      'servidor se hace aparte, cuando la haya.',
              alineaArriba: true,
              accion: state.hayCola ? state.textoSyncCorto : null,
              onAccion: state.hayCola
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SincronizacionScreen()))
                  : null,
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
            if (!remoto && !config.consentimientoAprobadoPorCei) ...[
              const SizedBox(height: 12),
              const StatusBanner(
                texto: 'La aprobación del centro o el consentimiento vigente '
                    'aún no están disponibles en este aparato. No se admite '
                    'el enrolamiento.',
                alineaArriba: true,
              ),
            ],

            const SizedBox(height: 22),
            LabeledField(
                label: 'Usuario',
                controller: _usuario,
                hint:
                    remoto ? 'correo@institucion.cu' : 'Ej.: investigador.uno'),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Contraseña',
              controller: _clave,
              oculto: true,
              onSubmitted: (_) {
                if (!_entrando) _entrar();
              },
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              StatusBanner(texto: _error!, alineaArriba: true),
            ],

            if (!remoto) ...[
              const SizedBox(height: 22),
              const SectionLabel('Función en el ensayo'),
              const SizedBox(height: 6),
              const Text(
                  'El diseño del ensayo separa funciones por razones '
                  'metodológicas: quien selecciona pacientes está cegado a la '
                  'secuencia, y quien evalúa desenlaces, a la rama asignada. '
                  'Elegir una rellena el usuario, y al revés.',
                  style: TextStyle(
                      fontSize: 12, color: T.secondary, height: 1.45)),
              const SizedBox(height: 12),
              for (final i in Seed.investigadores) ...[
                _OpcionFuncion(
                  investigador: i,
                  seleccionado: _seleccionado.id == i.id,
                  onTap: () => _elegir(i),
                ),
                const SizedBox(height: 8),
              ],
            ],

            const SizedBox(height: 20),
            AppButton(_entrando ? 'Entrando…' : 'Entrar',
                enabled: !_entrando, onTap: _entrar),
            if (remoto) ...[
              TextButton(
                onPressed: _entrando
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SolicitarAccesoScreen())),
                child: const Text('Solicitar acceso o crear cuenta'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _entrando || _recuperando ? null : _recuperarAcceso,
                child: Text(_recuperando
                    ? 'Solicitando…'
                    : '¿No recibió el correo? Enviar recuperación'),
              ),
            ],
            const SizedBox(height: 12),
            Text('v0.2.1 · ${config.definicionFormulario.version}',
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

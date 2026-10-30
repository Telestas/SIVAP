import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../data/remoto/autenticacion_firebase.dart';

/// Alta de cuenta y solicitud de perfil, sin permisos clínicos automáticos.
class SolicitarAccesoScreen extends StatefulWidget {
  const SolicitarAccesoScreen({super.key});

  @override
  State<SolicitarAccesoScreen> createState() => _SolicitarAccesoScreenState();
}

class _SolicitarAccesoScreenState extends State<SolicitarAccesoScreen>
    with WidgetsBindingObserver {
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  final _nombre = TextEditingController();
  final _centro = TextEditingController();
  bool _ocupado = false;
  bool _esperandoVerificacion = false;
  Timer? _comprobacion;
  String? _mensaje;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _esperandoVerificacion) {
      _comprobarVerificacion();
    }
  }

  @override
  void dispose() {
    _comprobacion?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _correo.dispose();
    _clave.dispose();
    _nombre.dispose();
    _centro.dispose();
    super.dispose();
  }

  void _esperarVerificacion() {
    _comprobacion?.cancel();
    _comprobacion = Timer.periodic(
        const Duration(seconds: 20), (_) => _comprobarVerificacion());
    setState(() {
      _esperandoVerificacion = true;
      _mensaje = const VerificacionPendiente().toString();
    });
  }

  Future<void> _comprobarVerificacion() async {
    if (!mounted || !_esperandoVerificacion || _ocupado) return;
    setState(() => _ocupado = true);
    try {
      await AppScope.read(context).solicitarAcceso(
          _correo.text, _clave.text, _nombre.text, _centro.text);
      if (!mounted) return;
      _comprobacion?.cancel();
      _clave.clear();
      setState(() {
        _esperandoVerificacion = false;
        _mensaje = 'Correo verificado. Solicitud enviada al investigador '
            'principal de su centro.';
      });
    } on VerificacionPendiente {
      // El enlace todavía no se abrió; se comprobará de nuevo al volver
      // a la app o en el siguiente intervalo.
    } on Object catch (error) {
      if (mounted) {
        setState(() => _mensaje = 'No se pudo comprobar la verificación: '
            '$error. Se reintentará automáticamente.');
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _enviar() async {
    if (_correo.text.trim().isEmpty ||
        _clave.text.isEmpty ||
        _nombre.text.trim().length < 2 ||
        _centro.text.trim().isEmpty) {
      setState(() => _mensaje = 'Complete todos los datos solicitados.');
      return;
    }
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    try {
      final estado = AppScope.read(context);
      try {
        await estado.crearCuenta(_correo.text, _clave.text);
      } on CuentaYaExiste {
        // El mismo formulario sirve para una cuenta ya creada.
      }
      await estado.solicitarAcceso(
          _correo.text, _clave.text, _nombre.text, _centro.text);
      _clave.clear();
      if (mounted) {
        setState(() => _mensaje = 'Solicitud enviada. El investigador '
            'principal de su centro debe aprobarla.');
      }
    } on VerificacionPendiente {
      if (mounted) _esperarVerificacion();
    } on Object catch (error) {
      if (mounted) setState(() => _mensaje = error.toString());
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Crear cuenta o solicitar acceso')),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                  'El correo es su identificador para entrar. Enviaremos la '
                  'solicitud con un solo toque; si la cuenta es nueva, se '
                  'activará para aprobación al verificar el correo.'),
              const SizedBox(height: 20),
              TextField(
                controller: _correo,
                enabled: !_esperandoVerificacion,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration:
                    const InputDecoration(labelText: 'Correo electrónico'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clave,
                enabled: !_esperandoVerificacion,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nombre,
                enabled: !_esperandoVerificacion,
                decoration: const InputDecoration(
                    labelText: 'Nombre visible (no es usuario)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _centro,
                enabled: !_esperandoVerificacion,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Código del centro', hintText: 'Ej.: C01'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _ocupado || _esperandoVerificacion ? null : _enviar,
                child: Text(_ocupado
                    ? 'Comprobando…'
                    : _esperandoVerificacion
                        ? 'Esperando verificación'
                        : 'Continuar'),
              ),
              if (_esperandoVerificacion)
                TextButton(
                  onPressed: () {
                    _comprobacion?.cancel();
                    setState(() => _esperandoVerificacion = false);
                  },
                  child: const Text('Cambiar datos'),
                ),
              if (_mensaje != null) ...[
                const SizedBox(height: 16),
                Text(_mensaje!),
              ],
            ],
          ),
        )),
      );
}

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../data/remoto/autenticacion_firebase.dart';

/// Alta de cuenta y solicitud de perfil, sin permisos clínicos automáticos.
class SolicitarAccesoScreen extends StatefulWidget {
  const SolicitarAccesoScreen({super.key});

  @override
  State<SolicitarAccesoScreen> createState() => _SolicitarAccesoScreenState();
}

class _SolicitarAccesoScreenState extends State<SolicitarAccesoScreen> {
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  final _nombre = TextEditingController();
  final _centro = TextEditingController();
  bool _ocupado = false;
  String? _mensaje;

  @override
  void dispose() {
    _correo.dispose();
    _clave.dispose();
    _nombre.dispose();
    _centro.dispose();
    super.dispose();
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
        if (mounted) {
          setState(
              () => _mensaje = 'Cuenta creada. Verifique el correo recibido y '
                  'pulse de nuevo «Continuar» para enviar la solicitud.');
        }
      } on CuentaYaExiste {
        await estado.solicitarAcceso(
            _correo.text, _clave.text, _nombre.text, _centro.text);
        if (mounted) {
          setState(() => _mensaje =
              'Solicitud enviada. El investigador principal de su centro debe aprobarla.');
        }
      }
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
                  'Escriba los datos de su cuenta. Si ya existe, enviaremos la solicitud; '
                  'si es nueva, primero deberá verificar el correo.'),
              const SizedBox(height: 20),
              TextField(
                controller: _correo,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration:
                    const InputDecoration(labelText: 'Correo electrónico'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clave,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nombre,
                decoration:
                    const InputDecoration(labelText: 'Nombre para el perfil'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _centro,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Código del centro', hintText: 'Ej.: C01'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _ocupado ? null : _enviar,
                child: Text(_ocupado ? 'Comprobando…' : 'Continuar'),
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

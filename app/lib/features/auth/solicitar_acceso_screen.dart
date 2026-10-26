import 'package:flutter/material.dart';

import '../../core/app_state.dart';

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
  bool _yaTieneCuenta = true;
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
        (_yaTieneCuenta &&
            (_nombre.text.trim().length < 2 || _centro.text.trim().isEmpty))) {
      setState(() => _mensaje = 'Complete todos los datos solicitados.');
      return;
    }
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    try {
      final estado = AppScope.read(context);
      if (_yaTieneCuenta) {
        await estado.solicitarAcceso(
            _correo.text, _clave.text, _nombre.text, _centro.text);
        if (mounted) {
          setState(() => _mensaje =
              'Solicitud enviada. El investigador principal de su centro debe aprobarla.');
        }
      } else {
        await estado.crearCuenta(_correo.text, _clave.text);
        if (mounted) {
          setState(() {
            _yaTieneCuenta = true;
            _mensaje = 'Cuenta creada. Verifique el correo recibido y después '
                'envíe la solicitud de acceso aquí.';
          });
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
        appBar: AppBar(title: const Text('Solicitar acceso')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
                'La cuenta necesita aprobación antes de abrir datos del estudio.'),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Ya tengo cuenta')),
                ButtonSegment(value: false, label: Text('Crear cuenta')),
              ],
              selected: {_yaTieneCuenta},
              onSelectionChanged: _ocupado
                  ? null
                  : (valor) => setState(() {
                        _yaTieneCuenta = valor.first;
                        _mensaje = null;
                      }),
            ),
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
            if (_yaTieneCuenta) ...[
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
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _ocupado ? null : _enviar,
              child: Text(_ocupado
                  ? 'Enviando…'
                  : _yaTieneCuenta
                      ? 'Enviar solicitud'
                      : 'Crear cuenta y verificar correo'),
            ),
            if (_mensaje != null) ...[
              const SizedBox(height: 16),
              Text(_mensaje!),
            ],
          ],
        ),
      );
}

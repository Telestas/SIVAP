import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/theme/tokens.dart';
import '../../data/remoto/actualizaciones.dart';

/// Aviso local de una nueva versión: no solicita permisos de notificación.
class CampanaActualizaciones extends StatelessWidget {
  const CampanaActualizaciones({super.key});

  @override
  Widget build(BuildContext context) {
    final actualizaciones = AppScope.of(context).actualizaciones;
    if (actualizaciones == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: actualizaciones,
      builder: (context, _) => IconButton(
        tooltip: actualizaciones.hayNuevaVersion
            ? 'Nueva versión disponible'
            : 'Notificaciones',
        onPressed: () => mostrarActualizaciones(context),
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_none_rounded, color: T.body),
            if (actualizaciones.hayNuevaVersion)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: T.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> mostrarActualizaciones(BuildContext context,
    {bool comprobarDeNuevo = false}) async {
  final actualizaciones = AppScope.read(context).actualizaciones;
  if (actualizaciones == null) return;
  if (comprobarDeNuevo || !actualizaciones.consultado) {
    // El diálogo se abre ya, de modo que también muestre la comprobación lenta.
    unawaited(actualizaciones.buscar(forzar: comprobarDeNuevo));
  }
  await showDialog<void>(
    context: context,
    builder: (context) => _DialogoActualizaciones(actualizaciones),
  );
}

class _DialogoActualizaciones extends StatelessWidget {
  const _DialogoActualizaciones(this.actualizaciones);

  final Actualizaciones actualizaciones;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: actualizaciones,
        builder: (context, _) => AlertDialog(
          title: const Text('Actualizaciones'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (actualizaciones.versionInstalada != null)
                Text('Versión instalada: ${actualizaciones.versionInstalada}'),
              const SizedBox(height: 12),
              if (actualizaciones.comprobando)
                const Text('Buscando nuevas versiones…')
              else if (actualizaciones.error != null)
                Text(actualizaciones.error!)
              else if (actualizaciones.hayNuevaVersion)
                Text('Tienes una nueva versión disponible: '
                    'v${actualizaciones.versionDisponible}.')
              else
                const Text('La app está actualizada.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: actualizaciones.comprobando
                  ? null
                  : () => actualizaciones.buscar(forzar: true),
              child: const Text('Buscar de nuevo'),
            ),
            if (actualizaciones.hayNuevaVersion)
              FilledButton(
                onPressed: () async {
                  var abierto = false;
                  try {
                    abierto = await actualizaciones.abrirPaginaDescarga();
                  } on Object {
                    abierto = false;
                  }
                  if (!context.mounted) return;
                  if (!abierto) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('No se pudo abrir la página de descarga.'),
                    ));
                  }
                },
                child: const Text('Descargar actualización'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
}

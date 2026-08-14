import 'dart:io';

import 'package:flutter/material.dart';

import '../screens/capture_mode_screen.dart';

/// Punto de entrada del flujo de captura de un ambiente: decide entre AR y
/// manual, y abre la pantalla correspondiente.
class ArCheckService {
  ArCheckService._();

  /// Empuja la pantalla completa de selección de modo
  /// ([CaptureModeScreen]).
  ///
  /// Antes esto era un `AlertDialog` con dos botones que aparecía sin
  /// contexto previo. Se promovió a pantalla completa porque la elección
  /// determina toda la pantalla siguiente (y puede derivar en un timeout de
  /// AR si el dispositivo no lo soporta) — ver `docs`/UX del selector en
  /// [CaptureModeScreen].
  static Future<void> elegirModoDeCaptura(
    BuildContext context, {
    required Widget pantallaEscaneoAR,
    required Widget pantallaManual,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaptureModeScreen(
          pantallaEscaneoAR: pantallaEscaneoAR,
          pantallaManual: pantallaManual,
        ),
      ),
    );
  }

  /// `true` si la plataforma es, en principio, compatible con el módulo AR.
  ///
  /// OJO: esto NO confirma que el hardware tenga ARCore/ARKit real — eso
  /// sólo se sabe al intentar inicializar `ARView` (ver el timeout de 8s en
  /// `ARScannerScreen`). Este chequeo únicamente descarta de entrada
  /// plataformas que directamente no van a poder correr el módulo (web,
  /// desktop).
  static bool get isPlatformSupported {
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      // Platform.* puede lanzar en entornos sin dart:io real (por ejemplo,
      // ciertos runners de test). Ante la duda, se trata como no soportado
      // y se ofrece el modo manual en vez de propagar la excepción.
      return false;
    }
  }

  /// Reemplaza la pantalla actual por el escaneo AR, o por el aviso de "no
  /// soportado" (con salida a modo manual) si la plataforma no es
  /// compatible.
  static void abrirEscaneoAR(
    BuildContext context, {
    required Widget pantallaEscaneoAR,
    required Widget pantallaManual,
  }) {
    if (isPlatformSupported) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => pantallaEscaneoAR),
      );
    } else {
      _mostrarAvisoNoSoportado(context, pantallaManual);
    }
  }

  /// Diálogo mostrado cuando la plataforma no puede ejecutar el módulo de
  /// AR de la aplicación; ofrece pasar directamente a [pantallaManual].
  static void _mostrarAvisoNoSoportado(BuildContext context, Widget pantallaManual) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 28,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Realidad Aumentada no disponible',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'Este dispositivo o plataforma no puede ejecutar el módulo '
            'de Realidad Aumentada.\n\n'
            'En Android se requiere compatibilidad con ARCore y en iOS '
            'compatibilidad con ARKit.\n\n'
            'Podés usar "Cargar manualmente" para crear el plano a mano.',
            style: TextStyle(
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => pantallaManual),
                );
              },
              child: const Text('Cargar manualmente'),
            ),
          ],
        );
      },
    );
  }
}

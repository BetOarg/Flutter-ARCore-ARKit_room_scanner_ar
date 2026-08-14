import 'package:flutter/material.dart';

import '../services/ar_check_service.dart';

/// Pantalla completa para elegir el modo de captura de un ambiente (AR o
/// manual).
///
/// Antes esta elección vivía en un `AlertDialog` con dos botones sueltos y
/// sin contexto. Se promovió a pantalla completa porque la decisión
/// determina toda la pantalla siguiente — y en el caso de AR, puede derivar
/// en un timeout de inicialización si el dispositivo no tiene soporte real
/// de ARCore/ARKit — así que amerita espacio para explicar brevemente cada
/// opción en vez de un ícono + una palabra.
class CaptureModeScreen extends StatelessWidget {
  final Widget pantallaEscaneoAR;
  final Widget pantallaManual;

  const CaptureModeScreen({
    super.key,
    required this.pantallaEscaneoAR,
    required this.pantallaManual,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('¿Cómo querés cargar el ambiente?')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Podés escanear con la cámara o dibujar el contorno a mano '
                'y anotar las medidas con una cinta métrica.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _ModeCard(
                        icon: Icons.view_in_ar,
                        title: 'Escanear con AR',
                        description: 'Apuntá la cámara a las paredes y '
                            'marcá las esquinas sobre la imagen real.',
                        recommendation:
                            'Recomendado si tu dispositivo soporta '
                            'ARCore/ARKit.',
                        color: Colors.blueAccent,
                        onTap: () => ArCheckService.abrirEscaneoAR(
                          context,
                          pantallaEscaneoAR: pantallaEscaneoAR,
                          pantallaManual: pantallaManual,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ModeCard(
                        icon: Icons.edit_note,
                        title: 'Manual',
                        description: 'Dibujá el contorno tocando la '
                            'pantalla y anotá las medidas reales.',
                        recommendation:
                            'Recomendado si no tenés AR o preferís mayor '
                            'precisión manual.',
                        color: Colors.teal,
                        onTap: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => pantallaManual),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String recommendation;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.recommendation,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56, color: color),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              Text(
                recommendation,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

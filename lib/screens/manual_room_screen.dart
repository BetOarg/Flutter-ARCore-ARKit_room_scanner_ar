import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/scanner_provider.dart';
import '../services/geometry_service.dart';
import '../utils/room_close_helper.dart';
import '../utils/scan_validator.dart';
import '../widgets/room_saved_sheet.dart';
import 'floor_plan_viewer_screen.dart';

enum _ManualMode { wall, door, window }

/// Carga manual de una habitación para dispositivos sin ARCore/ARKit (o para
/// cualquiera que prefiera no usar la cámara).
///
/// El usuario dibuja el contorno tocando la pantalla para marcar la
/// *dirección* de cada esquina nueva; como una pantalla no tiene forma de
/// saber la distancia real sin un sensor, se le pide la medida real de cada
/// pared (con cinta métrica) en vez de inventar una escala a partir de los
/// píxeles tocados — así los m² y el perímetro que calcula
/// [GeometryService] son datos reales, no una aproximación de la posición
/// del dedo en la pantalla.
///
/// Comparte `ScannerProvider`/`FloorPlanProvider` con `ARScannerScreen`, así
/// que toda la validación geométrica ([ScanValidator]) y el guardado
/// (`closeAndPersistRoom`) son exactamente los mismos que en el flujo AR.
class ManualRoomScreen extends StatefulWidget {
  final String projectUuid;
  final String projectName;

  const ManualRoomScreen({
    super.key,
    required this.projectUuid,
    required this.projectName,
  });

  @override
  State<ManualRoomScreen> createState() => _ManualRoomScreenState();
}

class _ManualRoomScreenState extends State<ManualRoomScreen> {
  _ManualMode _currentMode = _ManualMode.wall;

  static const double _pixelsPerMeter = 60.0;
  Offset? _originScreen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ScannerProvider>().startNewRoom();
    });
  }

  // ================================================================
  // TRANSFORMACIÓN MUNDO <-> PANTALLA
  //
  // Escala fija + origen fijo (se define una sola vez, al primer layout):
  // a diferencia del plano final (FloorPlanViewerScreen), que reencuadra
  // automáticamente porque solo se usa para ver/exportar, acá el lienzo NO
  // se puede reacomodar en cada punto nuevo o el usuario perdería la
  // referencia de hacia dónde estaba apuntando.
  // ================================================================

  Offset _worldToScreen(ARPoint p) {
    final origin = _originScreen!;
    return Offset(
      origin.dx + p.x * _pixelsPerMeter,
      origin.dy + p.z * _pixelsPerMeter,
    );
  }

  ARPoint _screenToWorld(Offset screen) {
    final origin = _originScreen!;
    return ARPoint(
      x: (screen.dx - origin.dx) / _pixelsPerMeter,
      y: 0,
      z: (screen.dy - origin.dy) / _pixelsPerMeter,
    );
  }

  // ================================================================
  // CAPTURA DE PUNTOS / ABERTURAS
  // ================================================================

  Future<void> _onCanvasTap(Offset localPos) async {
    final provider = context.read<ScannerProvider>();
    final points = provider.currentRoom?.points ?? const <ARPoint>[];

    if (_currentMode == _ManualMode.wall) {
      await _handleWallTap(localPos, points, provider);
    } else {
      _handleFeatureTap(localPos, points, provider);
    }
  }

  Future<void> _handleWallTap(
    Offset localPos,
    List<ARPoint> points,
    ScannerProvider provider,
  ) async {
    HapticFeedback.lightImpact();

    if (points.isEmpty) {
      // Primera esquina: se coloca directamente donde se tocó, sin pedir
      // longitud (todavía no hay ningún segmento del cual medir).
      final worldPoint = _screenToWorld(localPos);
      final result = provider.tryAddPoint(worldPoint.x, 0, worldPoint.z);
      _showValidation(result, provider);
      return;
    }

    final last = points.last;
    final lastScreen = _worldToScreen(last);
    final direction = localPos - lastScreen;

    if (direction.distance < 8) {
      // Toque demasiado cerca del punto anterior: no alcanza para definir
      // una dirección confiable.
      return;
    }

    final unit = direction / direction.distance;
    final suggested = direction.distance / _pixelsPerMeter;

    final length = await _promptLength(suggested: suggested);
    if (!mounted || length == null || length <= 0) return;

    final newX = last.x + unit.dx * length;
    final newZ = last.z + unit.dy * length;

    final result = provider.tryAddPoint(newX, 0, newZ);
    _showValidation(result, provider);
  }

  void _handleFeatureTap(
    Offset localPos,
    List<ARPoint> points,
    ScannerProvider provider,
  ) {
    if (points.length < 2) {
      _showSnack(
        'Necesitás marcar al menos 2 esquinas antes de agregar una abertura.',
        Colors.orange,
      );
      return;
    }

    HapticFeedback.lightImpact();

    final type = _currentMode == _ManualMode.door ? FeatureType.door : FeatureType.window;
    final label = _currentMode == _ManualMode.door ? 'Puerta' : 'Ventana';
    final worldPoint = _screenToWorld(localPos);

    provider.addFeatureToCurrentRoom(type, worldPoint);
    _showSnack('$label marcada en la posición actual', Colors.blueGrey, seconds: 1);
  }

  Future<double?> _promptLength({required double suggested}) {
    final controller = TextEditingController(
      text: suggested > 0.05 ? suggested.toStringAsFixed(2) : '',
    );
    return showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Longitud real de la pared'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            suffixText: 'm',
            border: OutlineInputBorder(),
            helperText: 'Medí con cinta métrica y escribí el valor real.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final normalized = controller.text.trim().replaceAll(',', '.');
              final value = double.tryParse(normalized);
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  void _showValidation(ValidationResult result, ScannerProvider provider) {
    if (!mounted) return;
    if (!result.isValid) {
      _showSnack(result.errorMessage ?? 'Punto inválido.', Colors.redAccent);
      return;
    }
    if (result.warningMessage != null) {
      // Igual que en el flujo AR: la sugerencia de "¿cerrar el recinto?"
      // ahora ofrece la acción directamente en el SnackBar, en vez de ser
      // solo texto informativo que obligaba a ir a buscar el botón de
      // cerrar por separado.
      _showSnack(
        result.warningMessage!,
        Colors.amber.shade800,
        seconds: 4,
        action: provider.currentPointsCount >= 3
            ? SnackBarAction(
                label: 'CERRAR',
                textColor: Colors.white,
                onPressed: () => _onClosePressed(provider),
              )
            : null,
      );
    }
  }

  void _showSnack(String message, Color color, {int seconds = 3, SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: seconds),
        action: action,
      ),
    );
  }

  // ================================================================
  // CIERRE Y PERSISTENCIA
  // ================================================================

  Future<void> _onClosePressed(ScannerProvider provider) async {
    HapticFeedback.mediumImpact();

    final result = await closeAndPersistRoom(
      scannerProvider: provider,
      floorPlanProvider: context.read<FloorPlanProvider>(),
    );

    if (!mounted) return;

    // Misma hoja de confirmación que en el flujo AR (ver
    // `showRoomCloseResultSheet`): reemplaza al SnackBar + pop automático
    // que había antes y le da al usuario un cierre explícito, sea éxito o
    // error.
    final action = await showRoomCloseResultSheet(context, result: result);
    if (!mounted) return;

    switch (action) {
      case RoomSavedAction.scanAnother:
        provider.startNewRoom();
        break;
      case RoomSavedAction.viewFloorPlan:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const FloorPlanViewerScreen()),
        );
        break;
      case RoomSavedAction.reviewPoints:
      case RoomSavedAction.dismiss:
        break;
    }
  }

  void _openFloorPlan() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FloorPlanViewerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScannerProvider>();
    final room = provider.currentRoom;
    final points = room?.points ?? const <ARPoint>[];
    final features = room?.features ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(room?.name ?? 'Carga manual (sin AR)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Ver plano del proyecto',
            onPressed: _openFloorPlan,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              points.isEmpty
                  ? 'Tocá el lienzo para marcar la primera esquina.'
                  : 'Tocá hacia donde sigue la pared: te vamos a pedir la '
                      'medida real (cinta métrica) para esa pared.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: RoomType.values.map((type) {
                  final isSelected = provider.selectedType == type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(type.name.toUpperCase()),
                      selected: isSelected,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        provider.setRoomType(type);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildModeChip(_ManualMode.wall, Icons.wallpaper, 'Pared'),
                const SizedBox(width: 8),
                _buildModeChip(_ManualMode.door, Icons.door_front_door, 'Puerta'),
                const SizedBox(width: 8),
                _buildModeChip(_ManualMode.window, Icons.window, 'Ventana'),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _originScreen ??= Offset(
                  constraints.biggest.width / 2,
                  constraints.biggest.height / 2,
                );

                return ClipRect(
                  child: InteractiveViewer(
                    boundaryMargin: const EdgeInsets.all(400),
                    minScale: 0.4,
                    maxScale: 4.0,
                    child: GestureDetector(
                      onTapUp: (details) => _onCanvasTap(details.localPosition),
                      child: CustomPaint(
                        size: constraints.biggest,
                        painter: _ManualCanvasPainter(
                          points: points,
                          features: features,
                          origin: _originScreen!,
                          pixelsPerMeter: _pixelsPerMeter,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: points.isNotEmpty
                        ? () {
                            HapticFeedback.lightImpact();
                            provider.removeLastPoint();
                          }
                        : null,
                    icon: const Icon(Icons.undo),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      points.length >= 3
                          ? '${points.length} esquinas · '
                              '${GeometryService.calculateArea(points).toStringAsFixed(2)} m²'
                          : '${points.length} esquina(s)',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    onPressed: points.length >= 3 ? () => _onClosePressed(provider) : null,
                    icon: const Icon(Icons.check),
                    style: IconButton.styleFrom(
                      backgroundColor: points.length >= 3 ? Colors.green : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(_ManualMode mode, IconData icon, String label) {
    final isSelected = _currentMode == mode;
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (!selected) return;
        HapticFeedback.selectionClick();
        setState(() => _currentMode = mode);
      },
    );
  }
}

class _ManualCanvasPainter extends CustomPainter {
  final List<ARPoint> points;
  final List<WallFeature> features;
  final Offset origin;
  final double pixelsPerMeter;

  const _ManualCanvasPainter({
    required this.points,
    required this.features,
    required this.origin,
    required this.pixelsPerMeter,
  });

  Offset _transform(ARPoint p) => Offset(
        origin.dx + p.x * pixelsPerMeter,
        origin.dy + p.z * pixelsPerMeter,
      );

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);

    final wallPaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final roomFill = Paint()
      ..color = Colors.blueAccent.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final cornerPaint = Paint()..color = Colors.white;

    final doorPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final windowPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    if (points.length >= 2) {
      final path = Path();
      final start = _transform(points.first);
      path.moveTo(start.dx, start.dy);
      for (var i = 1; i < points.length; i++) {
        final next = _transform(points[i]);
        path.lineTo(next.dx, next.dy);
      }
      if (points.length >= 3) path.close();

      if (points.length >= 3) canvas.drawPath(path, roomFill);
      canvas.drawPath(path, wallPaint);

      // Etiqueta de longitud real sobre cada tramo confirmado.
      final segmentCount = points.length >= 3 ? points.length : points.length - 1;
      for (var i = 0; i < segmentCount; i++) {
        final a = points[i];
        final b = points[(i + 1) % points.length];
        final mid = Offset(
          (_transform(a).dx + _transform(b).dx) / 2,
          (_transform(a).dy + _transform(b).dy) / 2,
        );
        _drawLabel(canvas, mid, '${GeometryService.calculateDistance(a, b).toStringAsFixed(2)} m');
      }
    }

    for (final p in points) {
      canvas.drawCircle(_transform(p), 5, cornerPaint);
    }

    for (final feature in features) {
      final pStart = _transform(feature.start);
      final pEnd = _transform(feature.end);
      canvas.drawLine(
        pStart,
        pEnd,
        feature.type == FeatureType.door ? doorPaint : windowPaint,
      );
    }
  }

  void _drawLabel(Canvas canvas, Offset pos, String text) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black54,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, pos - Offset(textPainter.width / 2, textPainter.height / 2));
  }

  void _paintGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;

    final step = pixelsPerMeter; // una línea por metro
    for (double x = origin.dx % step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = origin.dy % step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Marca el origen (primera esquina) para dar referencia visual.
    final originPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(origin.dx - 10, origin.dy),
      Offset(origin.dx + 10, origin.dy),
      originPaint,
    );
    canvas.drawLine(
      Offset(origin.dx, origin.dy - 10),
      Offset(origin.dx, origin.dy + 10),
      originPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ManualCanvasPainter oldDelegate) => true;
}

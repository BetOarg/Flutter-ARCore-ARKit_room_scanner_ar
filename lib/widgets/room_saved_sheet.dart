import 'package:flutter/material.dart';

import '../services/geometry_service.dart';
import '../utils/room_close_helper.dart';

/// Acción elegida por el usuario en la hoja mostrada al cerrar una
/// habitación (ver [showRoomCloseResultSheet]).
enum RoomSavedAction {
  /// Empezar a trazar otra habitación en el mismo proyecto/pantalla.
  scanAnother,

  /// Ir al plano general del proyecto.
  viewFloorPlan,

  /// El cierre falló: volver al lienzo a corregir los puntos trazados.
  reviewPoints,

  /// La hoja se cerró sin elegir nada (por ejemplo, en un cierre exitoso
  /// donde `isDismissible` permite deslizarla hacia abajo).
  dismiss,
}

/// Muestra una hoja inferior de confirmación al cerrar una habitación,
/// usada tanto por el flujo de escaneo AR como por la carga manual.
///
/// Antes, cerrar una habitación terminaba en un `SnackBar` genérico
/// seguido de un `Navigator.pop` inmediato: no había ningún momento
/// explícito de "listo, se guardó", ni indicación de qué hacer a
/// continuación, y un cierre fallido se reportaba igual (solo cambiaba el
/// color del SnackBar). Esta hoja separa claramente el caso de éxito
/// (resumen + dos acciones siguientes con sentido) del caso de error
/// (motivo + volver a revisar sin perder lo ya trazado).
Future<RoomSavedAction> showRoomCloseResultSheet(
  BuildContext context, {
  required RoomCloseResult result,
}) async {
  final action = await showModalBottomSheet<RoomSavedAction>(
    context: context,
    // Un cierre fallido no se puede descartar arrastrando la hoja: el
    // usuario tiene que reconocer el motivo del error de forma explícita
    // (leerlo) antes de volver al lienzo, en vez de que desaparezca solo.
    isDismissible: result.isSuccess,
    isScrollControlled: true,
    builder: (sheetContext) => _RoomSavedSheetContent(result: result),
  );
  return action ?? RoomSavedAction.dismiss;
}

class _RoomSavedSheetContent extends StatelessWidget {
  final RoomCloseResult result;

  const _RoomSavedSheetContent({required this.result});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children:
              result.isSuccess ? _buildSuccess(context) : _buildFailure(context),
        ),
      ),
    );
  }

  List<Widget> _buildSuccess(BuildContext context) {
    final room = result.room!;
    final area = GeometryService.calculateArea(room.points);

    return [
      Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Ambiente guardado',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        '${room.name} · ${room.points.length} paredes',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      Text(
        'Área aproximada: ${area.toStringAsFixed(2)} m²',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: () => Navigator.pop(context, RoomSavedAction.scanAnother),
        icon: const Icon(Icons.add_home_work_outlined),
        label: const Text('Escanear otro ambiente'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => Navigator.pop(context, RoomSavedAction.viewFloorPlan),
        icon: const Icon(Icons.map_outlined),
        label: const Text('Ver plano completo'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    ];
  }

  List<Widget> _buildFailure(BuildContext context) {
    return [
      Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No se pudo guardar el ambiente',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        result.error ?? 'Revisá los puntos trazados e intentá cerrar de nuevo.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: () => Navigator.pop(context, RoomSavedAction.reviewPoints),
        icon: const Icon(Icons.edit_location_alt_outlined),
        label: const Text('Revisar puntos'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    ];
  }
}

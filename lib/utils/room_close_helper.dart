import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/scanner_provider.dart';

/// Resultado de intentar cerrar la habitación en curso.
class RoomCloseResult {
  final RoomModel? room;
  final String? error;

  const RoomCloseResult._({this.room, this.error});

  bool get isSuccess => room != null;

  factory RoomCloseResult.success(RoomModel room) => RoomCloseResult._(room: room);
  factory RoomCloseResult.failure(String error) => RoomCloseResult._(error: error);
}

/// Cierra la habitación en curso de [scannerProvider] (validando geometría) y,
/// si tuvo éxito, la persiste a través de [floorPlanProvider].
///
/// Centraliza el flujo de "cerrar + guardar" para que tanto el escaneo AR
/// como la carga manual (sin AR) usen exactamente el mismo camino de
/// validación y persistencia en vez de reimplementarlo cada uno por su
/// cuenta.
Future<RoomCloseResult> closeAndPersistRoom({
  required ScannerProvider scannerProvider,
  required FloorPlanProvider floorPlanProvider,
}) async {
  final closedRoom = scannerProvider.closeCurrentRoom();

  if (closedRoom == null) {
    return RoomCloseResult.failure(
      scannerProvider.lastCloseError ??
          'No se pudo cerrar la habitación. Revisa los puntos trazados.',
    );
  }

  await floorPlanProvider.addCompletedRoom(closedRoom);

  // `addCompletedRoom` nunca relanza la excepción de guardado (ver
  // `FloorPlanProvider._persist`): hay que consultar `lastPersistError`
  // explícitamente para saber si la persistencia realmente funcionó, en
  // vez de asumir éxito solo porque la geometría pasó la validación. Antes
  // esta función declaraba éxito en este punto sin chequear nada más, así
  // que un fallo de guardado (disco lleno, DB corrupta, etc.) terminaba
  // mostrándole "¡Ambiente guardado correctamente!" al usuario con nada
  // realmente guardado.
  if (floorPlanProvider.lastPersistError != null) {
    return RoomCloseResult.failure(floorPlanProvider.lastPersistError!);
  }

  return RoomCloseResult.success(closedRoom);
}

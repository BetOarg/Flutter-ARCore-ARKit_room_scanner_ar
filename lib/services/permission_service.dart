import 'package:permission_handler/permission_handler.dart';

/// Gestiona los permisos en tiempo de ejecución que la app realmente
/// necesita para escanear.
///
/// Antes también se exigía `Permission.locationWhenInUse` junto con la
/// cámara (`cameraGranted && locationGranted`), aunque ninguna función de
/// la app usa datos de ubicación: no hay geocoding, no hay etiquetado GPS
/// de proyectos, `ARLocationManager` se recibe del plugin AR pero nunca se
/// consulta. En la práctica, cualquier usuario que rechazara el permiso de
/// ubicación —algo muy plausible en una app que a simple vista no
/// debería necesitarlo para medir un ambiente— quedaba completamente
/// bloqueado para escanear, aunque la cámara sí estuviera concedida.
/// Pedir un permiso que no se usa es además un problema de privacidad en
/// sí mismo y un motivo común de rechazo en la revisión de las tiendas de
/// apps.
class PermissionService {
  /// Solicita el permiso de cámara, el único que el escaneo AR
  /// efectivamente necesita.
  static Future<bool> requestScannerPermissions() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Verifica si el permiso de cámara ya fue concedido.
  static Future<bool> hasBasicPermissions() async {
    return Permission.camera.status.isGranted;
  }
}

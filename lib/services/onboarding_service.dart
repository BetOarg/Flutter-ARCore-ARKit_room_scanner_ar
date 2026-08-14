import 'package:shared_preferences/shared_preferences.dart';

/// Persiste si el usuario ya vio la introducción de la app (3 slides) para
/// no repetirla en cada apertura.
///
/// Se guarda con `shared_preferences` porque es una preferencia puramente
/// local del dispositivo, no un dato de proyecto (no tiene sentido
/// sincronizarla con Supabase ni guardarla en Isar junto con las
/// habitaciones escaneadas).
class OnboardingService {
  OnboardingService._();

  static const _seenKey = 'onboarding_seen_v1';

  /// Devuelve `true` si el usuario ya completó u omitió la introducción.
  ///
  /// Ante cualquier falla de lectura (por ejemplo, un problema de storage
  /// en el primer arranque) se asume `false` en vez de propagar la
  /// excepción: en el peor caso se vuelve a mostrar la introducción una vez
  /// de más, pero nunca se bloquea el arranque de la app por esto.
  static Future<bool> hasSeenOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_seenKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Marca la introducción como vista.
  ///
  /// Si falla el guardado no se propaga el error: como mucho, se le vuelve
  /// a mostrar la introducción al usuario la próxima vez que abra la app,
  /// una degradación aceptable frente a romper la navegación.
  static Future<void> markOnboardingSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {
      // Degradación silenciosa: ver docstring de arriba.
    }
  }
}

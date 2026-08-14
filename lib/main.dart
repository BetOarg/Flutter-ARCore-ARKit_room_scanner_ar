import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'models/room_model.dart';
import 'providers/scanner_provider.dart';
import 'providers/floor_plan_provider.dart';
import 'providers/project_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/onboarding_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Aviso de desarrollo (nunca en release): si se olvida pasar
  // --dart-define=SUPABASE_URL/SUPABASE_ANON_KEY al compilar, la app
  // arranca igual mostrando el placeholder, y el único síntoma era un
  // error de red genérico recién en el primer login o sincronización, sin
  // ninguna pista de la causa real.
  if (kDebugMode) _warnIfUsingPlaceholderSupabaseCredentials();

  // 1. Inicializar Supabase
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProjectProvider()),
        ChangeNotifierProvider(create: (_) => ScannerProvider()),
        // FloorPlanProvider es el estado en memoria del proyecto abierto;
        // se conecta aquí a ProjectProvider (Isar) como su única vía de
        // persistencia durable, en vez de guardar por su cuenta en un
        // archivo aparte como hacía antes.
        ChangeNotifierProxyProvider<ProjectProvider, FloorPlanProvider>(
          create: (_) => FloorPlanProvider(),
          update: (_, projectProvider, floorPlanProvider) {
            final provider = floorPlanProvider ?? FloorPlanProvider();
            provider.persister = ({
              required String uuid,
              required String name,
              required List<RoomModel> rooms,
            }) =>
                projectProvider.saveCurrentProject(uuid: uuid, name: name, rooms: rooms);
            return provider;
          },
        ),
      ],
      child: const RoomScannerApp(),
    ),
  );
}

void _warnIfUsingPlaceholderSupabaseCredentials() {
  const placeholderUrl = 'https://tu-proyecto.supabase.co';
  const placeholderKey = 'tu-anon-key-aqui';

  if (SupabaseConfig.supabaseUrl == placeholderUrl ||
      SupabaseConfig.supabaseAnonKey == placeholderKey) {
    debugPrint(
      '⚠️  Supabase está usando credenciales de placeholder. Compilá con '
      '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... '
      'o el login y la sincronización con la nube van a fallar.',
    );
  }
}

class RoomScannerApp extends StatelessWidget {
  const RoomScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Room Scanner AR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _AppRoot(),
    );
  }
}

/// Punto de entrada real de la app: decide entre mostrar la introducción
/// (primera vez), el login o el dashboard — en ese orden de prioridad.
///
/// La introducción se resuelve antes que el login a propósito: el usuario
/// necesita entender qué hace la app (y que existen dos modos de captura)
/// antes de que se le pida que se registre o continúe en modo offline.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  final _authService = AuthService();
  late final Future<bool> _hasSeenOnboardingFuture = OnboardingService.hasSeenOnboarding();

  // Una vez que el usuario termina la introducción en esta sesión, no hace
  // falta esperar a que `SharedPreferences` confirme el guardado para
  // dejarlo avanzar: se refleja de inmediato en memoria.
  bool _onboardingJustCompleted = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasSeenOnboardingFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !_onboardingJustCompleted) {
          return const _SplashScreen();
        }

        final hasSeenOnboarding = _onboardingJustCompleted || (snapshot.data ?? false);

        if (!hasSeenOnboarding) {
          return OnboardingScreen(
            onFinish: () => setState(() => _onboardingJustCompleted = true),
          );
        }

        return StreamBuilder<AuthState>(
          stream: _authService.authStateChanges,
          builder: (context, authSnapshot) {
            final session = _authService.currentUser;
            return session != null ? const DashboardScreen() : const LoginScreen();
          },
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

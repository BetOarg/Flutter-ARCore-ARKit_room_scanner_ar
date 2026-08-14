import 'package:flutter/foundation.dart';
import '../models/isar_models.dart';
import '../models/room_model.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';

class ProjectProvider with ChangeNotifier {
  final LocalDatabaseService _dbService = LocalDatabaseService();
  final SyncService _syncService = SyncService();

  List<IsarProject> _projects = [];
  IsarProject? _currentProject;
  bool _isLoading = false;
  String? _initError;

  List<IsarProject> get projects => _projects;
  IsarProject? get currentProject => _currentProject;
  bool get isLoading => _isLoading;

  /// Mensaje del último fallo al inicializar/cargar la base de datos local,
  /// o `null` si no hubo ninguno.
  String? get initError => _initError;

  /// Inicializa la base de datos y carga los proyectos guardados.
  ///
  /// Antes no tenía manejo de errores: si `_dbService.init()` fallaba (por
  /// ejemplo, un archivo de base de datos corrupto o sin espacio en
  /// disco), la excepción se propagaba sin control y `_setLoading(false)`
  /// nunca llegaba a ejecutarse — el dashboard quedaba mostrando el
  /// spinner de carga para siempre, sin ningún mensaje ni forma de
  /// reintentar.
  Future<void> init() async {
    _setLoading(true);
    _initError = null;
    try {
      await _dbService.init();
      await loadProjects();
    } catch (e) {
      _initError = 'No se pudo abrir la base de datos local: $e';
      debugPrint(_initError);
    } finally {
      _setLoading(false);
    }
  }

  /// Carga la lista de proyectos desde Isar
  Future<void> loadProjects() async {
    _projects = await _dbService.getAllProjects();
    notifyListeners();
  }

  /// Crea o guarda un proyecto existente (Persistencia Isar DB + Nube Supabase)
  Future<void> saveCurrentProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) async {
    _setLoading(true);

    // 1. Guardado en base de datos local (Isar DB)
    await _dbService.saveProject(
      uuid: uuid,
      name: name,
      rooms: rooms,
    );

    // 2. Sincronización en segundo plano con Supabase
    try {
      final roomsData = rooms.map((room) => room.toJson()).toList();
      await _syncService.syncProjectToCloud(
        projectId: uuid,
        name: name,
        projectData: {'rooms': roomsData},
      );
    } catch (e) {
      // Si no hay conexión o falla la nube, la información ya quedó segura en Isar
      debugPrint('Sincronización en la nube en espera/fallida: $e');
    }

    await loadProjects();
    _setLoading(false);
  }

  /// Carga un proyecto para trabajar en él
  Future<List<RoomModel>> selectProject(IsarProject project) async {
    _currentProject = project;
    notifyListeners();
    return await _dbService.getRoomsForProject(project.uuid);
  }

  /// Lee las habitaciones de un proyecto sin cambiar cuál es el proyecto
  /// actualmente seleccionado ni disparar `notifyListeners` — a diferencia
  /// de [selectProject].
  ///
  /// Pensado para lecturas de solo consulta que no deberían tener efectos
  /// secundarios sobre el resto de la UI, como la miniatura del plano en
  /// cada tarjeta del dashboard (`ProjectThumbnail`): si usara
  /// `selectProject`, mostrar la lista de proyectos terminaría pisando
  /// silenciosamente cuál es el proyecto "actual" con el último que se
  /// renderizó.
  Future<List<RoomModel>> loadRoomsPreview(String uuid) {
    return _dbService.getRoomsForProject(uuid);
  }

  /// Elimina un proyecto por su UUID
  Future<void> deleteProject(String uuid) async {
    _setLoading(true);
    await _dbService.deleteProject(uuid);
    if (_currentProject?.uuid == uuid) {
      _currentProject = null;
    }
    await loadProjects();
    _setLoading(false);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
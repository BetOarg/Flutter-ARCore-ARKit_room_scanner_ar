import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/isar_models.dart';
import '../providers/project_provider.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/scanner_provider.dart';
import '../services/auth_service.dart';
import '../services/ar_check_service.dart';
import 'ar_scanner_screen.dart';
import 'floor_plan_viewer_screen.dart';
import 'login_screen.dart';
import 'manual_room_screen.dart';
import '../widgets/project_thumbnail.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _authService = AuthService();
  bool _creatingProject = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectProvider>().init();
    });
  }

  void _showNewProjectDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo Proyecto'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Ej: Remodelación Oficina',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => _createProject(ctx, controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  Future<void> _createProject(BuildContext dialogContext, String name) async {
    // Protege contra un doble-tap en "Crear" antes de que el diálogo
    // termine de cerrarse: sin esto, dos disparos casi simultáneos podían
    // generar dos proyectos (potencialmente con el mismo uuid, si caían en
    // el mismo milisegundo) a partir de un solo toque percibido por el
    // usuario.
    if (name.isEmpty || _creatingProject) return;
    _creatingProject = true;
    Navigator.pop(dialogContext);

    final uuid = DateTime.now().millisecondsSinceEpoch.toString();

    try {
      // Crea el registro del proyecto en Isar (antes esto nunca se hacía:
      // el diálogo "Nuevo Proyecto" descartaba el nombre y jamás llegaba a
      // guardar nada, así que la lista de proyectos del dashboard nunca
      // crecía después de escanear).
      await context.read<ProjectProvider>().saveCurrentProject(
            uuid: uuid,
            name: name,
            rooms: const [],
          );
    } catch (e) {
      // Antes no había ningún manejo de error acá: si el guardado inicial
      // fallaba (disco lleno, DB corrupta), la excepción quedaba sin
      // capturar y el usuario se quedaba sin ningún mensaje ni forma de
      // saber que la creación del proyecto había fallado.
      _creatingProject = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo crear el proyecto: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    _creatingProject = false;
    if (!mounted) return;

    context.read<FloorPlanProvider>().loadProject(uuid: uuid, name: name, rooms: const []);
    context.read<ScannerProvider>().loadRooms(const []);

    await ArCheckService.elegirModoDeCaptura(
      context,
      pantallaEscaneoAR: ARScannerScreen(projectUuid: uuid, projectName: name),
      pantallaManual: ManualRoomScreen(projectUuid: uuid, projectName: name),
    );
  }

  Future<void> _openProject(IsarProject project) async {
    final provider = context.read<ProjectProvider>();
    final rooms = await provider.selectProject(project);

    if (!mounted) return;

    context.read<FloorPlanProvider>().loadProject(
          uuid: project.uuid,
          name: project.name,
          rooms: rooms,
        );
    context.read<ScannerProvider>().loadRooms(rooms);

    await ArCheckService.elegirModoDeCaptura(
      context,
      pantallaEscaneoAR: ARScannerScreen(projectUuid: project.uuid, projectName: project.name),
      pantallaManual: ManualRoomScreen(projectUuid: project.uuid, projectName: project.name),
    );
  }

  Future<void> _viewFloorPlan(IsarProject project) async {
    final provider = context.read<ProjectProvider>();
    final rooms = await provider.selectProject(project);

    if (!mounted) return;

    context.read<FloorPlanProvider>().loadProject(
          uuid: project.uuid,
          name: project.name,
          rooms: rooms,
        );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FloorPlanViewerScreen()),
    );
  }

  /// Pide confirmación antes de borrar un proyecto: es una acción
  /// destructiva e irreversible (borra también todas sus habitaciones
  /// guardadas), y antes se ejecutaba directamente al tocar el ícono de
  /// basura, sin ningún paso intermedio.
  Future<void> _confirmDelete(BuildContext context, IsarProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar proyecto?'),
        content: Text(
          'Se va a eliminar "${project.name}" junto con todos sus '
          'ambientes guardados. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.15),
              foregroundColor: Colors.red,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await context.read<ProjectProvider>().deleteProject(project.uuid);
  }

  void _handleSignOut() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final user = _authService.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Proyectos AR'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Cerrar Sesión',
            onPressed: _handleSignOut,
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de estado de conexión / usuario
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  user != null ? Icons.cloud_done : Icons.cloud_off,
                  color: user != null ? Colors.green : Colors.orangeAccent,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    user != null
                        ? 'Sincronizado: ${user.email}'
                        : 'Modo Offline (Proyectos guardados localmente)',
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Lista, estado vacío o error de carga
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : provider.initError != null
                    ? _buildErrorState(provider)
                    : provider.projects.isEmpty
                        ? _buildEmptyState()
                        : _buildProjectList(provider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewProjectDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Escaneo'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.architecture_rounded, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No tienes proyectos guardados',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          const Text('Presiona "Nuevo Escaneo" para comenzar'),
        ],
      ),
    );
  }

  /// Antes, un fallo al abrir la base de datos local (`ProjectProvider.
  /// init`) dejaba el dashboard mostrando el spinner de carga para
  /// siempre, sin ningún mensaje ni forma de reintentar. Este estado le da
  /// al usuario algo concreto para hacer en vez de una pantalla
  /// aparentemente colgada.
  Widget _buildErrorState(ProjectProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            const Text(
              'No se pudieron cargar tus proyectos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              provider.initError!,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => provider.init(),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectList(ProjectProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.projects.length,
      itemBuilder: (context, index) {
        final project = provider.projects[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: ProjectThumbnail(projectUuid: project.uuid),
            title: Text(
              project.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Actualizado: ${project.updatedAt.day}/${project.updatedAt.month}/${project.updatedAt.year}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.add_home_work_outlined),
                  tooltip: 'Agregar ambiente',
                  onPressed: () => _openProject(project),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Eliminar',
                  onPressed: () => _confirmDelete(context, project),
                ),
              ],
            ),
            // Tocar la tarjeta abre directamente el plano ya generado (lo
            // que la mayoría espera al abrir un proyecto existente); antes
            // reabría el selector de modo de captura incluso para
            // proyectos ya completos, lo cual sorprendía a cualquiera que
            // solo quisiera revisar un plano viejo. Agregar un ambiente
            // nuevo es ahora una acción explícita (ícono de arriba).
            onTap: () => _viewFloorPlan(project),
          ),
        );
      },
    );
  }
}

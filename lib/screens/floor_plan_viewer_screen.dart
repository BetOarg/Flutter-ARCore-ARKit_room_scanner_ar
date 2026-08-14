import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';
import '../services/geometry_service.dart';
import '../services/import_export_service.dart';

class FloorPlanViewerScreen extends StatefulWidget {
  const FloorPlanViewerScreen({super.key});

  @override
  State<FloorPlanViewerScreen> createState() => _FloorPlanViewerScreenState();
}

class _FloorPlanViewerScreenState extends State<FloorPlanViewerScreen> {
  // Solo conservamos minX y minZ para la transformación
  double _minX = 0.0;
  double _minZ = 0.0;
  double _scale = 1.0;
  double _padding = 20.0;

  // Convierte coordenadas del plano a pantalla
  Offset _transformPoint(ARPoint p) {
    final x = _padding + (p.x - _minX) * _scale;
    final z = _padding + (p.z - _minZ) * _scale;
    return Offset(x, z);
  }

  // Convierte coordenadas de pantalla a plano (inversa)
  ARPoint _inverseTransform(Offset screenPos) {
    final x = (screenPos.dx - _padding) / _scale + _minX;
    final z = (screenPos.dy - _padding) / _scale + _minZ;
    return ARPoint(x: x, y: 0.0, z: z);
  }

  // Calcula la escala y límites según las habitaciones cargadas
  void _calculateTransform(Size screenSize, List<RoomModel> rooms) {
    if (rooms.isEmpty) return;

    double minX = double.infinity, maxX = double.negativeInfinity;
    double minZ = double.infinity, maxZ = double.negativeInfinity;

    for (var room in rooms) {
      for (var p in room.points) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.z < minZ) minZ = p.z;
        if (p.z > maxZ) maxZ = p.z;
      }
    }

    _minX = minX;
    _minZ = minZ;

    _padding = screenSize.width * 0.1;
    final contentWidth = (maxX - minX) == 0 ? 1.0 : (maxX - minX);
    final contentHeight = (maxZ - minZ) == 0 ? 1.0 : (maxZ - minZ);

    _scale = ((screenSize.width - 2 * _padding) / contentWidth)
        .clamp(0.0, (screenSize.height - 2 * _padding) / contentHeight);
  }

  // Retorna el ID de la habitación tocada
  String? _getRoomAtPosition(ARPoint point, List<RoomModel> rooms) {
    for (var room in rooms) {
      if (GeometryService.isPointInPolygon(point, room.points)) {
        return room.id;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Antes el título era un texto fijo ("Plano General 2D") sin
        // relación con el proyecto que se estaba viendo — con varios
        // proyectos, esta pantalla no daba ninguna pista de en cuál estabas
        // parado. Ahora muestra el nombre real y es editable: además,
        // `FloorPlanProvider.setProjectName` existía desde hacía tiempo sin
        // ningún lugar en la UI que lo llamara (no había forma de renombrar
        // un proyecto una vez creado).
        title: Consumer<FloorPlanProvider>(
          builder: (context, provider, _) => InkWell(
            onTap: () => _editProjectName(context, provider),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(provider.projectName, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit, size: 16),
              ],
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Importar Plano',
            onPressed: () async {
              final provider = context.read<FloorPlanProvider>();
              final success = await ImportExportService.importFromJson(provider);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Plano importado con éxito' : 'Error o importación cancelada',
                    ),
                    backgroundColor: success ? Colors.green : Colors.orange,
                  ),
                );
              }
            },
          ),
          // Antes había dos íconos sueltos (compartir JSON / exportar PDF)
          // al mismo nivel jerárquico, aunque para la mayoría de usuarios
          // el PDF es la exportación que realmente van a usar (para
          // mandarle el plano a alguien) y el JSON es un formato técnico de
          // respaldo. Un solo botón "Exportar" con las dos opciones
          // etiquetadas deja esa diferencia explícita en vez de forzar al
          // usuario a adivinar qué ícono corresponde a cada cosa.
          PopupMenuButton<_ExportOption>(
            icon: const Icon(Icons.share),
            tooltip: 'Exportar',
            onSelected: (option) => _handleExport(context, option),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ExportOption.pdf,
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('PDF'),
                  subtitle: Text('Para compartir'),
                ),
              ),
              PopupMenuItem(
                value: _ExportOption.json,
                child: ListTile(
                  leading: Icon(Icons.description_outlined),
                  title: Text('JSON'),
                  subtitle: Text('Respaldo de datos'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showRoomListDialog(context),
        child: const Icon(Icons.edit_note),
      ),
      body: Consumer<FloorPlanProvider>(
        builder: (context, provider, child) {
          final rooms = provider.completedRooms;

          if (rooms.isEmpty) {
            return const Center(
              child: Text('No hay ambientes escaneados aún.'),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              _calculateTransform(constraints.biggest, rooms);

              return InteractiveViewer(
                boundaryMargin: const EdgeInsets.all(100),
                minScale: 0.1,
                maxScale: 4.0,
                child: GestureDetector(
                  onTapUp: (details) {
                    final localOffset = details.localPosition;
                    final planePoint = _inverseTransform(localOffset);

                    final roomId = _getRoomAtPosition(planePoint, rooms);
                    if (roomId != null) {
                      _showAddFeatureMenu(context, roomId, planePoint);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Toca dentro de un ambiente para añadir puertas o ventanas'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: FloorPlanPainter(
                      rooms: rooms,
                      transform: _transformPoint,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _handleExport(BuildContext context, _ExportOption option) async {
    final provider = context.read<FloorPlanProvider>();

    // Antes se podía "exportar" un proyecto sin ambientes: el PDF salía con
    // el título y ningún contenido, y el JSON era `{"rooms": []}` — un
    // artefacto sin utilidad, sin ningún aviso de que no había nada que
    // exportar todavía.
    if (provider.completedRooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todavía no hay ambientes para exportar.')),
      );
      return;
    }

    final success = switch (option) {
      _ExportOption.pdf =>
        await ImportExportService.exportToPdf(provider.completedRooms, provider.projectName),
      _ExportOption.json =>
        await ImportExportService.exportToJson(provider.completedRooms, provider.projectName),
    };

    // Antes ninguno de los dos métodos de exportación tenía manejo de
    // errores en la pantalla: si `Printing.layoutPdf` o `Share.shareXFiles`
    // fallaban (sin apps de destino, sin espacio, etc.), no había ningún
    // mensaje — la exportación simplemente no pasaba nada, sin explicación.
    if (!context.mounted || success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo completar la exportación. Intentá de nuevo.'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _showAddFeatureMenu(BuildContext context, String roomId, ARPoint location) {
    // Se guarda la referencia al context de la pantalla (no el de la hoja
    // modal, que se desmonta al cerrarla) para poder mostrar feedback
    // después de que termine el guardado.
    final screenContext = context;

    Future<void> addFeature(FeatureType type, double offsetX) async {
      final endPoint = ARPoint(x: location.x + offsetX, y: location.y, z: location.z);
      final provider = screenContext.read<FloorPlanProvider>();
      await provider.addFeatureToRoom(roomId, type, location, endPoint);

      // Antes esta llamada era "fire and forget": si la persistencia
      // fallaba, no había ningún indicio para el usuario de que la puerta
      // o ventana recién agregada no había quedado realmente guardada.
      if (!screenContext.mounted || provider.lastPersistError == null) return;
      ScaffoldMessenger.of(screenContext).showSnackBar(
        SnackBar(
          content: Text(provider.lastPersistError!),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Agregar elemento a esta habitación'),
              leading: Icon(Icons.add_location_alt),
            ),
            ListTile(
              leading: const Icon(Icons.door_front_door, color: Colors.red),
              title: const Text('Puerta'),
              onTap: () {
                Navigator.pop(sheetContext);
                addFeature(FeatureType.door, 0.8);
              },
            ),
            ListTile(
              leading: const Icon(Icons.window, color: Colors.blue),
              title: const Text('Ventana'),
              onTap: () {
                Navigator.pop(sheetContext);
                addFeature(FeatureType.window, 1.0);
              },
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  void _showRoomListDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Consumer<FloorPlanProvider>(
          builder: (context, provider, child) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ambientes registrados',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (provider.completedRooms.isEmpty)
                    const Center(child: Text('No hay ambientes aún.'))
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: provider.completedRooms.length,
                      itemBuilder: (context, index) {
                        final room = provider.completedRooms[index];
                        final summary = provider.roomSummaries[index];
                        return ListTile(
                          leading: const Icon(Icons.house),
                          title: Text(room.name),
                          subtitle: Text(
                            'Área: ${summary['area']} m² · ${room.points.length} pts · ${room.features.length} elementos',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editRoomName(context, room),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editProjectName(BuildContext context, FloorPlanProvider provider) async {
    final controller = TextEditingController(text: provider.projectName);
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renombrar proyecto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Nombre del proyecto',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              Navigator.pop(dialogContext);
              if (newName.isNotEmpty && newName != provider.projectName) {
                provider.setProjectName(newName);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editRoomName(BuildContext context, RoomModel room) async {
    final controller = TextEditingController(text: room.name);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renombrar Ambiente'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Nuevo nombre',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                context.read<FloorPlanProvider>().updateRoomName(room.id, newName);
              }
              Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

/// Opciones del menú "Exportar" del plano general.
enum _ExportOption { pdf, json }

class FloorPlanPainter extends CustomPainter {
  final List<RoomModel> rooms;
  final Offset Function(ARPoint) transform;

  const FloorPlanPainter({
    required this.rooms,
    required this.transform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rooms.isEmpty) return;

    final wallPaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final roomFill = Paint()
      ..color = Colors.blueAccent.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final doorPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final windowPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    for (var room in rooms) {
      if (room.points.length >= 2) {
        final path = Path();
        final start = transform(room.points.first);
        path.moveTo(start.dx, start.dy);

        for (var i = 1; i < room.points.length; i++) {
          final next = transform(room.points[i]);
          path.lineTo(next.dx, next.dy);
        }
        path.close();

        canvas.drawPath(path, roomFill);
        canvas.drawPath(path, wallPaint);
      }

      if (room.points.isNotEmpty) {
        final labelPos = transform(room.points.first);
        final textSpan = TextSpan(
          text: room.name,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, labelPos + const Offset(5, 5));
      }

      for (var feature in room.features) {
        final pStart = transform(feature.start);
        final pEnd = transform(feature.end);

        if (feature.type == FeatureType.door) {
          canvas.drawLine(pStart, pEnd, doorPaint);
        } else {
          canvas.drawLine(pStart, pEnd, windowPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
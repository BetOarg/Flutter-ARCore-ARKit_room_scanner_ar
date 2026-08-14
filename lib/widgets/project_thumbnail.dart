import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/room_model.dart';
import '../providers/project_provider.dart';

/// Miniatura del plano de un proyecto, usada en las tarjetas del dashboard.
///
/// Carga las habitaciones del proyecto de forma perezosa y aislada del
/// resto del estado de la app: usa
/// [ProjectProvider.loadRoomsPreview] en lugar de `selectProject`, que
/// además cambia cuál es "el proyecto actualmente seleccionado" — mostrar
/// una miniatura en una lista no debería tener ese efecto secundario.
class ProjectThumbnail extends StatefulWidget {
  final String projectUuid;
  final double size;

  const ProjectThumbnail({
    super.key,
    required this.projectUuid,
    this.size = 48,
  });

  @override
  State<ProjectThumbnail> createState() => _ProjectThumbnailState();
}

class _ProjectThumbnailState extends State<ProjectThumbnail> {
  // Se dispara una única vez en `initState` y se cachea acá. Antes se
  // llamaba a `loadRoomsPreview` directamente dentro de `build()` de un
  // `StatelessWidget`: cada reconstrucción del dashboard (por ejemplo, al
  // cambiar `ProjectProvider.isLoading` durante *cualquier* operación, no
  // solo una relacionada con este proyecto) creaba un `Future` nuevo con
  // identidad distinta, lo que reiniciaba el `FutureBuilder` a su estado de
  // carga y disparaba una consulta redundante a Isar por cada tarjeta
  // visible — un parpadeo del spinner y lecturas de disco de más en cada
  // rebuild, no solo cuando el proyecto realmente cambia.
  late final Future<List<RoomModel>> _roomsFuture =
      context.read<ProjectProvider>().loadRoomsPreview(widget.projectUuid);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: FutureBuilder<List<RoomModel>>(
            future: _roomsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }

              // Ante error de lectura o un proyecto sin ambientes todavía,
              // se cae a un ícono neutro en vez de propagar la excepción:
              // una miniatura rota no debería tirar abajo el resto de la
              // lista de proyectos del dashboard.
              final rooms = snapshot.data ?? const <RoomModel>[];
              final hasDrawableRoom = rooms.any((r) => r.points.length >= 2);

              if (snapshot.hasError || !hasDrawableRoom) {
                return Icon(
                  Icons.meeting_room,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                );
              }

              return CustomPaint(
                painter: _RoomFootprintPainter(
                  rooms: rooms,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Dibuja el contorno agregado de todas las habitaciones de un proyecto,
/// reencuadrado para ocupar el tamaño disponible. Es una versión mínima del
/// mismo cálculo de transformación que usa `FloorPlanViewerScreen`, pero
/// sin grilla, etiquetas ni interacción — solo la silueta.
class _RoomFootprintPainter extends CustomPainter {
  final List<RoomModel> rooms;
  final Color color;

  const _RoomFootprintPainter({required this.rooms, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minZ = double.infinity, maxZ = double.negativeInfinity;

    for (final room in rooms) {
      for (final p in room.points) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.z < minZ) minZ = p.z;
        if (p.z > maxZ) maxZ = p.z;
      }
    }

    if (minX.isInfinite || maxX.isInfinite) return;

    const padding = 4.0;
    final contentWidth = (maxX - minX) <= 0 ? 1.0 : (maxX - minX);
    final contentHeight = (maxZ - minZ) <= 0 ? 1.0 : (maxZ - minZ);
    final scale = ((size.width - padding * 2) / contentWidth)
        .clamp(0.0, (size.height - padding * 2) / contentHeight);

    Offset transform(ARPoint p) => Offset(
          padding + (p.x - minX) * scale,
          padding + (p.z - minZ) * scale,
        );

    final fillPaint = Paint()
      ..color = color.withOpacity(0.25)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (final room in rooms) {
      if (room.points.length < 2) continue;

      final path = Path();
      final start = transform(room.points.first);
      path.moveTo(start.dx, start.dy);
      for (var i = 1; i < room.points.length; i++) {
        final p = transform(room.points[i]);
        path.lineTo(p.dx, p.dy);
      }
      path.close();

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoomFootprintPainter oldDelegate) =>
      oldDelegate.rooms != rooms || oldDelegate.color != color;
}

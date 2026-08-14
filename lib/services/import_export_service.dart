import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';

class ImportExportService {
  ImportExportService._();

  /// Límite defensivo para archivos de importación: un JSON de miles de
  /// habitaciones no es un caso de uso real de esta app, así que un
  /// archivo mucho más grande que eso es más probable que sea un archivo
  /// corrupto (o pensado para otra cosa) que un plano legítimo. Sin este
  /// límite, `jsonDecode` se aplicaba sobre cualquier tamaño de archivo
  /// que el selector devolviera.
  static const int _maxImportBytes = 20 * 1024 * 1024; // 20 MB

  /// Exporta el proyecto a un archivo JSON real y abre el selector para
  /// compartirlo/guardarlo.
  ///
  /// Antes se compartía el JSON con `Share.share(jsonString, ...)`, que lo
  /// manda como texto plano: la mayoría de las apps de destino (mail,
  /// WhatsApp, etc.) lo tratan como un mensaje, no como un archivo adjunto,
  /// así que para un proyecto con varias habitaciones el "respaldo" podía
  /// llegar truncado, mal pegado, o simplemente sin forma fácil de
  /// guardarlo como archivo. Ahora se escribe un .json real y se comparte
  /// como adjunto.
  ///
  /// Devuelve `false` (sin lanzar) si no hay nada que exportar o si algo
  /// falla al escribir/compartir el archivo.
  static Future<bool> exportToJson(List<RoomModel> rooms, String projectName) async {
    if (rooms.isEmpty) return false;

    try {
      final data = {
        'projectName': projectName,
        'rooms': rooms.map((r) => r.toJson()).toList(),
      };
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);

      final tempDir = await getTemporaryDirectory();
      final safeName = projectName.trim().replaceAll(RegExp(r'[^\w\s-]'), '');
      final fileName = '${safeName.isEmpty ? 'plano' : safeName}.json';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(jsonString);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: '$projectName - Plano 2D',
      );
      return true;
    } catch (e) {
      debugPrint('Error exportando JSON: $e');
      return false;
    }
  }

  /// Importa un archivo JSON seleccionado desde el dispositivo.
  ///
  /// Devuelve `false` si el usuario cancela la selección, si el archivo
  /// supera [_maxImportBytes], o si el contenido no tiene la forma
  /// esperada (JSON inválido, sin `rooms`, etc.) — nunca lanza una
  /// excepción hacia la pantalla que lo llama.
  static Future<bool> importFromJson(FloorPlanProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.bytes == null) return false;

      final bytes = result.files.single.bytes!;
      if (bytes.lengthInBytes > _maxImportBytes) {
        debugPrint(
          'Archivo de importación demasiado grande '
          '(${bytes.lengthInBytes} bytes, máximo $_maxImportBytes).',
        );
        return false;
      }

      final fileContent = utf8.decode(bytes);
      final decoded = jsonDecode(fileContent);
      if (decoded is! Map<String, dynamic>) return false;

      final projectName = decoded['projectName'] as String? ?? 'Proyecto Importado';
      final roomsData = decoded['rooms'];
      if (roomsData is! List) return false;

      final rooms = roomsData
          .whereType<Map<String, dynamic>>()
          .map(RoomModel.fromJson)
          .toList();

      await provider.loadExistingRooms(rooms, projectName);
      return true;
    } catch (e) {
      // Cubre JSON inválido, campos con un tipo inesperado, o cualquier
      // otro archivo que no tenga la forma de un export de esta app.
      debugPrint('Error importando JSON: $e');
      return false;
    }
  }

  /// Genera un PDF básico del plano (resumen por ambiente, no un dibujo a
  /// escala del contorno) y abre la vista previa/impresión.
  ///
  /// Devuelve `false` si no hay ambientes para exportar o si falla la
  /// generación/impresión, en vez de dejar una excepción sin manejar.
  static Future<bool> exportToPdf(List<RoomModel> rooms, String projectName) async {
    if (rooms.isEmpty) return false;

    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(level: 0, child: pw.Text('Plano Arquitectónico: $projectName')),
                pw.SizedBox(height: 20),
                pw.Text('Resumen de Ambientes:'),
                pw.SizedBox(height: 10),
                ...rooms.map((room) => pw.Bullet(text: '${room.name}: ${room.points.length} vértices')),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
      return true;
    } catch (e) {
      debugPrint('Error exportando PDF: $e');
      return false;
    }
  }
}

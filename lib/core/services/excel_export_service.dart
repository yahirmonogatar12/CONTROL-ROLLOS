import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

class ExcelExportService {
  /// Exportar datos a archivo Excel
  /// [data] - Lista de mapas con los datos
  /// [headers] - Lista de headers para mostrar
  /// [fieldMapping] - Mapeo de campos de BD a columnas
  /// [fileName] - Nombre sugerido del archivo
  static Future<bool> exportToExcel({
    required List<Map<String, dynamic>> data,
    required List<String> headers,
    required List<String> fieldMapping,
    String fileName = 'export',
  }) async {
    try {
      // Crear libro Excel
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      
      // Agregar headers
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#1E5128'),
          fontColorHex: ExcelColor.white,
          horizontalAlign: HorizontalAlign.Center,
        );
      }
      
      // Agregar datos
      for (int rowIndex = 0; rowIndex < data.length; rowIndex++) {
        final row = data[rowIndex];
        for (int colIndex = 0; colIndex < fieldMapping.length; colIndex++) {
          final field = fieldMapping[colIndex];
          var value = row[field]?.toString() ?? '';
          
          // Campos de fecha con hora separada (formato: fecha|hora)
          final dateTimeFields = ['fecha_recibo', 'fecha_salida', 'fecha_registro'];
          
          // Formatear fecha (solo fecha sin hora)
          if (dateTimeFields.contains(field) && value.isNotEmpty) {
            try {
              // Manejar ambos formatos: "2026-01-20 00:01:10" o "2026-01-20T00:01:10"
              final isoValue = value.contains('T') ? value : value.replaceFirst(' ', 'T');
              final date = DateTime.parse(isoValue);
              value = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
            } catch (_) {}
          }
          
          // Formatear hora (campo especial con sufijo _hora)
          if (field.endsWith('_hora')) {
            final baseField = field.substring(0, field.length - 5); // Remover '_hora'
            final rawValue = row[baseField]?.toString() ?? '';
            if (rawValue.isNotEmpty) {
              try {
                // Manejar ambos formatos: "2026-01-20 00:01:10" o "2026-01-20T00:01:10"
                final isoValue = rawValue.contains('T') ? rawValue : rawValue.replaceFirst(' ', 'T');
                final date = DateTime.parse(isoValue);
                value = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
              } catch (_) {
                value = '';
              }
            } else {
              value = '';
            }
          }
          
          // Formatear estado_desecho
          if (field == 'estado_desecho') {
            value = value == '1' ? 'Yes' : 'No';
          }
          
          // Formatear cancelado
          if (field == 'cancelado') {
            value = value == '1' ? 'Yes' : 'No';
          }
          
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: rowIndex + 1));
          
          // Intentar poner como número si es numérico y válido
          final numValue = num.tryParse(value);
          if (numValue != null && !dateTimeFields.contains(field) && !field.endsWith('_hora') && numValue.isFinite) {
            cell.value = IntCellValue(numValue.toInt());
          } else {
            cell.value = TextCellValue(value);
          }
          
          // Alternar colores de fila
          if (rowIndex % 2 == 1) {
            cell.cellStyle = CellStyle(
              backgroundColorHex: ExcelColor.fromHexString('#F0F0F0'),
            );
          }
        }
      }
      
      // Auto-ajustar columnas (aproximado)
      for (int i = 0; i < headers.length; i++) {
        sheet.setColumnWidth(i, 18);
      }
      // Primera columna más ancha para el código
      sheet.setColumnWidth(0, 30);
      
      // Guardar archivo
      final timestamp = DateTime.now().toString().replaceAll(':', '-').split('.').first;
      final defaultFileName = '${fileName}_$timestamp.xlsx';
      
      // Mostrar diálogo para guardar
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar archivo Excel',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      
      if (outputPath == null) {
        return false; // Usuario canceló
      }
      
      // Asegurar extensión .xlsx
      final finalPath = outputPath.endsWith('.xlsx') ? outputPath : '$outputPath.xlsx';
      
      // Guardar archivo
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(finalPath);
        await file.writeAsBytes(fileBytes);
        print('✓ Excel exportado: $finalPath');
        return true;
      }
      
      return false;
    } catch (e) {
      print('Error exportando Excel: $e');
      return false;
    }
  }
}

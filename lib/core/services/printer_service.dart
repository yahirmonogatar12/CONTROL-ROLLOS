import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../config/server_config.dart';
import '../config/print_server_config.dart';

/// Print method options
enum PrintMethod {
  direct,      // Direct to printer (local/network)
  viaServer,   // Via print server (for mobile with Vercel backend)
}

class PrinterService {
  static const String _printerNameKey = 'selected_printer_name';
  static const String _printerUrlKey = 'selected_printer_url';
  static const String _printerIpKey = 'selected_printer_ip';
  static const String _printerPortKey = 'selected_printer_port';
  static const String _printMethodKey = 'print_method';
  
  static String? _selectedPrinterName;
  static String? _selectedPrinterUrl;
  static String? _printerIp;
  static int _printerPort = 9100;
  static PrintMethod _printMethod = PrintMethod.direct;
  
  // Inicializar el servicio cargando la impresora guardada
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedPrinterName = prefs.getString(_printerNameKey);
    _selectedPrinterUrl = prefs.getString(_printerUrlKey);
    _printerIp = prefs.getString(_printerIpKey);
    _printerPort = prefs.getInt(_printerPortKey) ?? 9100;
    
    // Load print method
    final methodIndex = prefs.getInt(_printMethodKey) ?? 0;
    _printMethod = PrintMethod.values[methodIndex.clamp(0, PrintMethod.values.length - 1)];
    
    // Also initialize print server config
    await PrintServerConfig.init();
  }
  
  /// Get current print method
  static PrintMethod get printMethod => _printMethod;
  
  /// Set print method
  static Future<void> setPrintMethod(PrintMethod method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_printMethodKey, method.index);
    _printMethod = method;
  }
  
  // Obtener lista de impresoras disponibles
  static Future<List<Printer>> getAvailablePrinters() async {
    try {
      final printers = await Printing.listPrinters();
      return printers;
    } catch (e) {
      print('Error al obtener impresoras: $e');
      return [];
    }
  }
  
  // Guardar impresora seleccionada
  static Future<void> setSelectedPrinter(Printer printer, {String? ip, int port = 9100}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerNameKey, printer.name);
    await prefs.setString(_printerUrlKey, printer.url);
    if (ip != null) {
      await prefs.setString(_printerIpKey, ip);
      await prefs.setInt(_printerPortKey, port);
      _printerIp = ip;
      _printerPort = port;
    }
    _selectedPrinterName = printer.name;
    _selectedPrinterUrl = printer.url;
  }

  /// Sync selected printer config to backend print service.
  /// Returns null on success, or an error message on failure.
  static Future<String?> syncServerPrinterConfig({
    required String printerName,
    String? printerIp,
    int printerPort = 9100,
  }) async {
    try {
      String url;

      // Prefer separate print server if configured; otherwise use active API server.
      if (PrintServerConfig.isEnabled && PrintServerConfig.isConfigured) {
        url = '${PrintServerConfig.baseUrl}/print/configure';
      } else {
        final server = ServerConfig.activeServer;
        if (server == null) {
          return 'No hay servidor configurado';
        }
        url = '${server.baseUrl}/print/configure';
      }

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'printerName': printerName,
              'printerIp': printerIp ?? '',
              'printerPort': printerPort,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['success'] == true) {
          return null;
        }
        return data['error'] ?? data['message'] ?? 'Error desconocido';
      }

      return 'Error del servidor: ${response.statusCode}';
    } on SocketException {
      return 'No se puede conectar al servidor';
    } on TimeoutException {
      return 'Tiempo de espera agotado';
    } catch (e) {
      return e.toString();
    }
  }
  
  // Guardar IP de impresora de red
  static Future<void> setPrinterNetworkConfig(String ip, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerIpKey, ip);
    await prefs.setInt(_printerPortKey, port);
    _printerIp = ip;
    _printerPort = port;
  }
  
  // Obtener configuración
  static String? get selectedPrinterName => _selectedPrinterName;
  static String? get selectedPrinterUrl => _selectedPrinterUrl;
  static String? get printerIp => _printerIp;
  static int get printerPort => _printerPort;
  
  // Verificar si hay impresora configurada
  static bool get hasPrinterConfigured => _selectedPrinterName != null && _selectedPrinterName!.isNotEmpty;
  static bool get hasNetworkConfig => _printerIp != null && _printerIp!.isNotEmpty;
  
  // Generar código ZPL para etiqueta
  static String generateLabelZPL({
    required String codigo,
    required String fecha,
    required String especificacion,
    required String cantidadActual,
  }) {
    // Dividir el código en 3 partes:
    // 1. Part Number (ej: EAX69577801)
    // 2. Versión PCB si existe (ej: V1.1)
    // 3. Lote (ej: 20260108001)
    // Maneja casos como: EAX69577801.1.1-20260108001 o EBK60752502-202511250001
    String partNumber = '';
    String version = '';
    String lote = '';
    
    // Buscar el guion para separar el lote
    final dashIndex = codigo.indexOf('-');
    if (dashIndex > 0) {
      final beforeDash = codigo.substring(0, dashIndex);
      lote = codigo.substring(dashIndex + 1);
      
      // Buscar versión PCB (patrón: .X.X donde X son números)
      // Ej: EAX69577801.1.1 -> partNumber=EAX69577801, version=V1.1
      final versionMatch = RegExp(r'^([A-Z0-9]+)\.(\d+\.\d+)$').firstMatch(beforeDash);
      if (versionMatch != null) {
        partNumber = versionMatch.group(1)!;
        version = 'V${versionMatch.group(2)}';
      } else {
        // Sin versión, todo es part number
        partNumber = beforeDash;
      }
    } else {
      partNumber = codigo;
    }
    
    // Dividir especificación en hasta 3 líneas si es muy larga
    // Máximo ~15 caracteres por línea para que quepa bien
    String especificacionLine1 = '';
    String especificacionLine2 = '';
    String especificacionLine3 = '';
    
    const int maxCharsPerLine = 15;
    
    if (especificacion.length <= maxCharsPerLine) {
      // Cabe en una línea
      especificacionLine1 = especificacion;
    } else if (especificacion.length <= maxCharsPerLine * 2 + 5) {
      // Dividir en 2 líneas
      final midPoint = especificacion.length ~/ 2;
      int splitIndex = especificacion.indexOf(' ', midPoint);
      if (splitIndex < 0) {
        splitIndex = especificacion.lastIndexOf(' ', midPoint);
      }
      if (splitIndex > 0) {
        especificacionLine1 = especificacion.substring(0, splitIndex);
        especificacionLine2 = especificacion.substring(splitIndex + 1);
      } else {
        // Sin espacios, cortar en el punto medio
        especificacionLine1 = especificacion.substring(0, midPoint);
        especificacionLine2 = especificacion.substring(midPoint);
      }
    } else {
      // Dividir en 3 líneas para especificaciones muy largas
      final thirdPoint = especificacion.length ~/ 3;
      final twoThirdPoint = (especificacion.length * 2) ~/ 3;
      
      // Buscar espacios cercanos a los puntos de división
      int splitIndex1 = especificacion.indexOf(' ', thirdPoint);
      if (splitIndex1 < 0 || splitIndex1 > thirdPoint + 5) {
        splitIndex1 = especificacion.lastIndexOf(' ', thirdPoint);
      }
      if (splitIndex1 < 0) splitIndex1 = thirdPoint;
      
      int splitIndex2 = especificacion.indexOf(' ', twoThirdPoint);
      if (splitIndex2 < 0 || splitIndex2 > twoThirdPoint + 5) {
        splitIndex2 = especificacion.lastIndexOf(' ', twoThirdPoint);
      }
      if (splitIndex2 < 0) splitIndex2 = twoThirdPoint;
      
      // Asegurar que splitIndex2 > splitIndex1
      if (splitIndex2 <= splitIndex1) {
        splitIndex2 = especificacion.indexOf(' ', splitIndex1 + 1);
        if (splitIndex2 < 0) splitIndex2 = ((splitIndex1 + especificacion.length) ~/ 2);
      }
      
      especificacionLine1 = especificacion.substring(0, splitIndex1).trim();
      especificacionLine2 = especificacion.substring(splitIndex1, splitIndex2).trim();
      especificacionLine3 = especificacion.substring(splitIndex2).trim();
    }
    
    // Plantilla ZPL con DataMatrix
    // Ajustamos posiciones verticales para acomodar 3 líneas de especificación
    final zpl = '''CT~~CD,~CC^~CT~
  ^XA
  ~TA000
  ~JSN
  ^LT37
  ^MNW
  ^MTT
  ^PON
  ^PMN
  ^LH0,0
  ^JMA
  ^PR4,4
  ~SD15
  ^JUS
  ^LRN
  ^CI27
  ^PA0,1,1,0
  ^XZ
  ^XA
  ^MMT
  ^PW392
  ^LL165
  ^LS0
  ^FT170,78^A0N,24,22^FH\\^CI28^FDQTY:^FS^CI27
  ^FT15,0^BXN,6,200
  ^FH\\^FD$codigo^FS
  ^FT170,-4^A0N,32,30^FH\\^CI28^FD$partNumber^FS^CI27
  ^FT170,26^A0N,28,26^FH\\^CI28^FD$version^FS^CI27
  ^FT170,52^A0N,26,24^FH\\^CI28^FD$lote^FS^CI27
  ^FT15,125^A0N,22,20^FH\\^CI28^FDFecha de entrada:^FS^CI27
  ^FT15,150^A0N,27,25^FH\\^CI28^FD$fecha^FS^CI27
  ^FT170,108^A0N,24,22^FH\\^CI28^FD$especificacionLine1^FS^CI27
  ^FT170,130^A0N,24,22^FH\\^CI28^FD$especificacionLine2^FS^CI27
  ^FT170,152^A0N,24,22^FH\\^CI28^FD$especificacionLine3^FS^CI27
  ^FT240,82^A0N,30,28^FH\\^CI28^FD$cantidadActual^FS^CI27
  ^PQ1,0,1,Y
  ^XZ''';
    
    return zpl;
  }

  /// Generar ZPL simplificado para impresión Bluetooth directa
  /// Sin prefijos de configuración, solo el código ZPL puro
  static String generateLabelZPLForBluetooth({
    required String codigo,
    required String fecha,
    required String especificacion,
    required String cantidadActual,
  }) {
    // Dividir el código igual que en generateLabelZPL
    String partNumber = '';
    String version = '';
    String lote = '';
    
    final dashIndex = codigo.indexOf('-');
    if (dashIndex > 0) {
      final beforeDash = codigo.substring(0, dashIndex);
      lote = codigo.substring(dashIndex + 1);
      
      final versionMatch = RegExp(r'^([A-Z0-9]+)\.(\d+\.\d+)$').firstMatch(beforeDash);
      if (versionMatch != null) {
        partNumber = versionMatch.group(1)!;
        version = 'V${versionMatch.group(2)}';
      } else {
        partNumber = beforeDash;
      }
    } else {
      partNumber = codigo;
    }
    
    // Dividir especificación en líneas
    String especificacionLine1 = '';
    String especificacionLine2 = '';
    String especificacionLine3 = '';
    
    const int maxCharsPerLine = 15;
    
    if (especificacion.length <= maxCharsPerLine) {
      especificacionLine1 = especificacion;
    } else if (especificacion.length <= maxCharsPerLine * 2 + 5) {
      final midPoint = especificacion.length ~/ 2;
      int splitIndex = especificacion.indexOf(' ', midPoint);
      if (splitIndex < 0) splitIndex = especificacion.lastIndexOf(' ', midPoint);
      if (splitIndex > 0) {
        especificacionLine1 = especificacion.substring(0, splitIndex);
        especificacionLine2 = especificacion.substring(splitIndex + 1);
      } else {
        especificacionLine1 = especificacion.substring(0, midPoint);
        especificacionLine2 = especificacion.substring(midPoint);
      }
    } else {
      final thirdPoint = especificacion.length ~/ 3;
      final twoThirdPoint = (especificacion.length * 2) ~/ 3;
      
      int splitIndex1 = especificacion.indexOf(' ', thirdPoint);
      if (splitIndex1 < 0 || splitIndex1 > thirdPoint + 5) {
        splitIndex1 = especificacion.lastIndexOf(' ', thirdPoint);
      }
      if (splitIndex1 < 0) splitIndex1 = thirdPoint;
      
      int splitIndex2 = especificacion.indexOf(' ', twoThirdPoint);
      if (splitIndex2 < 0 || splitIndex2 > twoThirdPoint + 5) {
        splitIndex2 = especificacion.lastIndexOf(' ', twoThirdPoint);
      }
      if (splitIndex2 < 0) splitIndex2 = twoThirdPoint;
      
      if (splitIndex2 <= splitIndex1) {
        splitIndex2 = especificacion.indexOf(' ', splitIndex1 + 1);
        if (splitIndex2 < 0) splitIndex2 = ((splitIndex1 + especificacion.length) ~/ 2);
      }
      
      especificacionLine1 = especificacion.substring(0, splitIndex1).trim();
      especificacionLine2 = especificacion.substring(splitIndex1, splitIndex2).trim();
      especificacionLine3 = especificacion.substring(splitIndex2).trim();
    }
    
    // ZPL simplificado para Bluetooth - Zebra ZQ310 Plus
    // Usando ^FO (Field Origin) en lugar de ^FT para mejor compatibilidad
    // Etiqueta de 50x25mm aproximadamente (400 dots x 200 dots a 8 dpmm)
    return '^XA\r\n'
        '^CI28\r\n'  // Codificación UTF-8
        '^PW400\r\n'  // Ancho de impresión
        '^LL200\r\n'  // Alto de etiqueta
        // DataMatrix código completo
        '^FO10,10^BXN,4,200^FD$codigo^FS\r\n'
        // Part Number
        '^FO150,10^A0N,25,25^FD$partNumber^FS\r\n'
        // Versión
        '^FO150,40^A0N,20,20^FD$version^FS\r\n'
        // Lote
        '^FO150,65^A0N,18,18^FD$lote^FS\r\n'
        // QTY label y valor
        '^FO150,90^A0N,20,20^FDQTY: $cantidadActual^FS\r\n'
        // Especificación (1 línea simplificada)
        '^FO150,115^A0N,16,16^FD${especificacion.length > 20 ? especificacion.substring(0, 20) : especificacion}^FS\r\n'
        // Fecha
        '^FO10,140^A0N,18,18^FDFecha: $fecha^FS\r\n'
        '^PQ1,0,1,Y\r\n'
        '^XZ\r\n';
  }
  
  // Imprimir etiqueta usando la impresora configurada
  static Future<bool> printLabel({
    required String codigo,
    required String fecha,
    required String especificacion,
    required String cantidadActual,
  }) async {
    print('=== PrinterService.printLabel ===');
    print('Generando ZPL...');
    
    final zpl = generateLabelZPL(
      codigo: codigo,
      fecha: fecha,
      especificacion: especificacion,
      cantidadActual: cantidadActual,
    );
    
    print('ZPL generado (${zpl.length} caracteres)');
    print('printMethod: $_printMethod');
    print('hasNetworkConfig: $hasNetworkConfig');
    print('hasPrinterConfigured: $hasPrinterConfigured');
    print('printerIp: $_printerIp');
    print('printerPort: $_printerPort');
    print('printerName: $_selectedPrinterName');
    
    // If using server method, send to print server
    if (_printMethod == PrintMethod.viaServer && PrintServerConfig.isEnabled) {
      print('Enviando vía servidor de impresión: ${PrintServerConfig.displayString}');
      return await PrintServerConfig.sendPrintJob(
        zplCode: zpl,
        printerIp: _printerIp,
        printerPort: _printerPort,
      );
    }
    
    // Direct printing methods
    // Si hay IP configurada, enviar por red (preferido para Zebra)
    if (hasNetworkConfig) {
      print('Enviando por red a $_printerIp:$_printerPort');
      return await printZPLToNetwork(zpl, _printerIp!, port: _printerPort);
    }
    
    // Intentar enviar usando impresión directa
    if (hasPrinterConfigured) {
      print('Enviando a impresora local: $_selectedPrinterName');
      return await printZPLDirect(zpl);
    }
    
    print('No hay impresora configurada');
    return false;
  }
  
  // Enviar ZPL directamente a la impresora (usando Windows Raw Print)
  static Future<bool> printZPLDirect(String zplCode) async {
    try {
      print('Enviando RAW a $_selectedPrinterName...');
      return await _printZPLRawWithPowerShell(zplCode);
    } catch (e) {
      print('Error al imprimir ZPL directo: $e');
      return false;
    }
  }
  
  // Método RAW usando PowerShell y .NET RawPrinterHelper
  static Future<bool> _printZPLRawWithPowerShell(String zplCode) async {
    try {
      // Guardar ZPL en archivo temporal
      final tempDir = Directory.systemTemp;
      final zplFile = File('${tempDir.path}\\zpl_${DateTime.now().millisecondsSinceEpoch}.txt');
      await zplFile.writeAsString(zplCode, flush: true);
      
      // Guardar script PS1 en archivo temporal
      final scriptFile = File('${tempDir.path}\\print_zpl_${DateTime.now().millisecondsSinceEpoch}.ps1');
      
      final scriptContent = '''
\$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class RawPrinterHelper
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public class DOCINFOA
    {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
    }

    [DllImport("winspool.Drv", EntryPoint = "OpenPrinterA", CharSet = CharSet.Ansi, SetLastError = true)]
    public static extern bool OpenPrinter([MarshalAs(UnmanagedType.LPStr)] string szPrinter, out IntPtr hPrinter, IntPtr pd);

    [DllImport("winspool.Drv", EntryPoint = "ClosePrinter", SetLastError = true)]
    public static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint = "StartDocPrinterA", CharSet = CharSet.Ansi, SetLastError = true)]
    public static extern bool StartDocPrinter(IntPtr hPrinter, Int32 level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFOA di);

    [DllImport("winspool.Drv", EntryPoint = "EndDocPrinter", SetLastError = true)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint = "StartPagePrinter", SetLastError = true)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint = "EndPagePrinter", SetLastError = true)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint = "WritePrinter", SetLastError = true)]
    public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, Int32 dwCount, out Int32 dwWritten);

    public static bool SendStringToPrinter(string szPrinterName, string szString)
    {
        IntPtr hPrinter = new IntPtr(0);
        DOCINFOA di = new DOCINFOA();
        di.pDocName = "ZPL Label";
        di.pDataType = "RAW";

        if (OpenPrinter(szPrinterName, out hPrinter, IntPtr.Zero))
        {
            if (StartDocPrinter(hPrinter, 1, di))
            {
                if (StartPagePrinter(hPrinter))
                {
                    byte[] bytes = System.Text.Encoding.ASCII.GetBytes(szString);
                    IntPtr pBytes = Marshal.AllocCoTaskMem(bytes.Length);
                    Marshal.Copy(bytes, 0, pBytes, bytes.Length);
                    int dwWritten = 0;
                    bool result = WritePrinter(hPrinter, pBytes, bytes.Length, out dwWritten);
                    Marshal.FreeCoTaskMem(pBytes);
                    EndPagePrinter(hPrinter);
                    EndDocPrinter(hPrinter);
                    ClosePrinter(hPrinter);
                    return result;
                }
                EndDocPrinter(hPrinter);
            }
            ClosePrinter(hPrinter);
        }
        return false;
    }
}
'@

\$zplContent = Get-Content -Path "${zplFile.path.replaceAll('\\', '/')}" -Raw -Encoding UTF8
\$printerName = "$_selectedPrinterName"
\$result = [RawPrinterHelper]::SendStringToPrinter(\$printerName, \$zplContent)
Write-Host "Resultado: \$result"
if (\$result) { exit 0 } else { exit 1 }
''';
      
      await scriptFile.writeAsString(scriptContent, flush: true);
      
      final result = await Process.run(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-File', scriptFile.path],
        runInShell: true,
      );
      
      // Limpiar archivos temporales
      try { await zplFile.delete(); } catch (_) {}
      try { await scriptFile.delete(); } catch (_) {}
      
      print('PowerShell stdout: ${result.stdout}');
      if (result.stderr.toString().isNotEmpty) {
        print('PowerShell stderr: ${result.stderr}');
      }
      
      if (result.exitCode == 0 && result.stdout.toString().contains('True')) {
        print('✓ ZPL enviado RAW exitosamente a $_selectedPrinterName');
        return true;
      } else {
        print('✗ Error al enviar RAW: exitCode=${result.exitCode}');
        return false;
      }
    } catch (e) {
      print('Error al imprimir RAW con PowerShell: $e');
      return false;
    }
  }
  
  /// Imprimir ZPL raw directamente sin generar
  /// Útil para etiquetas con formato personalizado ya generado
  static Future<bool> printRawZpl(String zplCode) async {
    print('=== PrinterService.printRawZpl ===');
    print('ZPL length: ${zplCode.length} caracteres');
    print('printMethod: $_printMethod');
    
    // If using server method, send to print server
    if (_printMethod == PrintMethod.viaServer && PrintServerConfig.isEnabled) {
      print('Enviando vía servidor de impresión: ${PrintServerConfig.displayString}');
      return await PrintServerConfig.sendPrintJob(
        zplCode: zplCode,
        printerIp: _printerIp,
        printerPort: _printerPort,
      );
    }
    
    // Direct printing methods
    if (hasNetworkConfig) {
      print('Enviando por red a $_printerIp:$_printerPort');
      return await printZPLToNetwork(zplCode, _printerIp!, port: _printerPort);
    }
    
    if (hasPrinterConfigured) {
      print('Enviando a impresora local: $_selectedPrinterName');
      return await printZPLDirect(zplCode);
    }
    
    print('No hay impresora configurada');
    return false;
  }
  
  // Enviar ZPL por socket (método para impresoras Zebra en red)
  static Future<bool> printZPLToNetwork(String zplCode, String ipAddress, {int port = 9100}) async {
    try {
      final socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 5));
      socket.write(zplCode);
      await socket.flush();
      await socket.close();
      print('ZPL enviado correctamente a $ipAddress:$port');
      return true;
    } catch (e) {
      print('Error al enviar ZPL por red: $e');
      return false;
    }
  }
  
  /// Imprimir múltiples etiquetas en batch (más eficiente)
  /// Combina todos los ZPL en uno solo y los envía de una vez
  static Future<Map<String, bool>> printLabelsBatch({
    required List<Map<String, String>> labels,
    required String fecha,
    required String especificacion,
    required String cantidadActual,
    void Function(int current, int total, String label)? onProgress,
  }) async {
    print('=== PrinterService.printLabelsBatch ===');
    print('Total de etiquetas: ${labels.length}');
    print('printMethod: $_printMethod');
    
    final Map<String, bool> results = {};
    
    if (labels.isEmpty) return results;
    
    // Generar todos los ZPL combinados
    final StringBuffer combinedZpl = StringBuffer();
    
    for (int i = 0; i < labels.length; i++) {
      final label = labels[i];
      final codigo = label['codigo'] ?? '';
      
      onProgress?.call(i + 1, labels.length, codigo);
      
      final zpl = generateLabelZPL(
        codigo: codigo,
        fecha: fecha,
        especificacion: especificacion,
        cantidadActual: cantidadActual,
      );
      
      combinedZpl.writeln(zpl);
      results[codigo] = true; // Asumimos éxito, se marcará como false si falla
    }
    
    final combinedZplString = combinedZpl.toString();
    print('ZPL combinado generado (${combinedZplString.length} caracteres para ${labels.length} etiquetas)');
    
    bool success = false;
    
    // If using server method, send to print server
    if (_printMethod == PrintMethod.viaServer && PrintServerConfig.isEnabled) {
      print('Enviando batch vía servidor de impresión: ${PrintServerConfig.displayString}');
      success = await PrintServerConfig.sendPrintJob(
        zplCode: combinedZplString,
        printerIp: _printerIp,
        printerPort: _printerPort,
      );
    }
    // Si hay IP configurada, enviar por red (más rápido)
    else if (hasNetworkConfig) {
      print('Enviando batch por red a $_printerIp:$_printerPort');
      success = await printZPLToNetwork(combinedZplString, _printerIp!, port: _printerPort);
    } else if (hasPrinterConfigured) {
      print('Enviando batch a impresora local: $_selectedPrinterName');
      success = await printZPLDirect(combinedZplString);
    }
    
    if (!success) {
      // Marcar todas como fallidas
      for (final label in labels) {
        results[label['codigo'] ?? ''] = false;
      }
    }
    
    print('Batch completado. Éxito: $success');
    return results;
  }
  
  // Limpiar configuración de impresora
  static Future<void> clearPrinterConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_printerNameKey);
    await prefs.remove(_printerUrlKey);
    await prefs.remove(_printerIpKey);
    await prefs.remove(_printerPortKey);
    _selectedPrinterName = null;
    _selectedPrinterUrl = null;
    _printerIp = null;
    _printerPort = 9100;
  }
}

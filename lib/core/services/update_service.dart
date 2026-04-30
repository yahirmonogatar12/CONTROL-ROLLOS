import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Configuración de GitHub para actualizaciones
class GitHubConfig {
  static const String owner = 'yahirmonogatar12';
  static const String repo = 'CONTROL-ROLLOS';
  static const String apiUrl = 'https://api.github.com/repos/$owner/$repo/releases/latest';
  static const String downloadUrl = 'https://github.com/$owner/$repo/releases/download';
}

/// Información de una actualización disponible
class UpdateInfo {
  final bool updateAvailable;
  final String currentVersion;
  final String latestVersion;
  final String? releaseDate;
  final String? downloadUrl;
  final String? releaseNotes;
  final bool isMandatory;

  UpdateInfo({
    required this.updateAvailable,
    required this.currentVersion,
    required this.latestVersion,
    this.releaseDate,
    this.downloadUrl,
    this.releaseNotes,
    this.isMandatory = false,
  });

  /// Crear desde respuesta de GitHub Releases API
  factory UpdateInfo.fromGitHub(Map<String, dynamic> json, String currentVersion) {
    // Obtener tag_name (ej: "v1.2.0" o "1.2.0")
    String tagName = json['tag_name']?.toString() ?? '';
    // Remover prefijo 'v' si existe
    String latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;
    
    // Comparar versiones
    final hasUpdate = _compareVersions(latestVersion, currentVersion) > 0;
    
    // Buscar el asset del instalador (.exe)
    String? downloadUrl;
    final assets = json['assets'] as List<dynamic>? ?? [];
    for (final asset in assets) {
      final name = asset['name']?.toString() ?? '';
      if (name.endsWith('.exe')) {
        downloadUrl = asset['browser_download_url']?.toString();
        break;
      }
    }
    
    // Si no hay asset, usar URL directa del release
    downloadUrl ??= json['html_url']?.toString();
    
    // Verificar si es pre-release (considerarlo como obligatorio si no lo es)
    final isPrerelease = json['prerelease'] == true;
    
    return UpdateInfo(
      updateAvailable: hasUpdate,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseDate: json['published_at']?.toString(),
      downloadUrl: downloadUrl,
      releaseNotes: json['body']?.toString(),
      isMandatory: !isPrerelease && hasUpdate, // Obligatorio si no es pre-release
    );
  }

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    // Handle isMandatory as int (0/1) or bool
    final mandatory = json['isMandatory'];
    final isMandatoryBool = mandatory == true || mandatory == 1 || mandatory == '1';
    
    // Handle updateAvailable as int (0/1) or bool
    final available = json['updateAvailable'];
    final updateAvailableBool = available == true || available == 1 || available == '1';
    
    return UpdateInfo(
      updateAvailable: updateAvailableBool,
      currentVersion: json['currentVersion']?.toString() ?? '',
      latestVersion: json['latestVersion']?.toString() ?? '',
      releaseDate: json['releaseDate']?.toString(),
      downloadUrl: json['downloadUrl']?.toString(),
      releaseNotes: json['releaseNotes']?.toString(),
      isMandatory: isMandatoryBool,
    );
  }
  
  /// Comparar dos versiones semánticas
  /// Retorna: >0 si v1 > v2, <0 si v1 < v2, 0 si son iguales
  static int _compareVersions(String v1, String v2) {
    try {
      final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      
      // Asegurar que ambas tengan al menos 3 partes
      while (parts1.length < 3) parts1.add(0);
      while (parts2.length < 3) parts2.add(0);
      
      for (int i = 0; i < 3; i++) {
        if (parts1[i] > parts2[i]) return 1;
        if (parts1[i] < parts2[i]) return -1;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }
}

/// Servicio para manejar actualizaciones de la aplicación
class UpdateService {
  static String? _currentVersion;
  static bool _isChecking = false;
  static bool _isDownloading = false;
  static double _downloadProgress = 0.0;
  
  /// Versión actual de la aplicación
  static String get currentVersion => _currentVersion ?? '0.0.0';
  
  /// Indica si está verificando actualizaciones
  static bool get isChecking => _isChecking;
  
  /// Indica si está descargando una actualización
  static bool get isDownloading => _isDownloading;
  
  /// Progreso de descarga (0.0 - 1.0)
  static double get downloadProgress => _downloadProgress;
  
  /// Cargar la versión actual desde VERSION.txt
  static Future<void> loadCurrentVersion() async {
    try {
      // En modo release, el VERSION.txt está en el directorio de la app
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      
      // Intentar diferentes ubicaciones
      final possiblePaths = [
        '$exeDir\\data\\flutter_assets\\assets\\VERSION.txt',
        '$exeDir\\VERSION.txt',
        'assets/VERSION.txt',
      ];
      
      for (final path in possiblePaths) {
        final file = File(path);
        if (await file.exists()) {
          _currentVersion = (await file.readAsString()).trim();
          debugPrint('📱 App version loaded: $_currentVersion from $path');
          return;
        }
      }
      
      // Si no se encuentra, usar versión por defecto
      _currentVersion = '1.0.0';
      debugPrint('⚠️ VERSION.txt not found, using default: $_currentVersion');
    } catch (e) {
      _currentVersion = '1.0.0';
      debugPrint('❌ Error loading version: $e');
    }
  }
  
  /// Verificar si hay actualizaciones disponibles (consulta GitHub Releases)
  static Future<UpdateInfo?> checkForUpdates() async {
    if (_isChecking) return null;
    
    try {
      _isChecking = true;
      
      // Asegurarse de que tenemos la versión actual
      if (_currentVersion == null) {
        await loadCurrentVersion();
      }
      
      debugPrint('🔍 Checking GitHub for updates...');
      debugPrint('📍 API URL: ${GitHubConfig.apiUrl}');
      
      final response = await http.get(
        Uri.parse(GitHubConfig.apiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'CONTROL-ROLLOS-App',
        },
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final updateInfo = UpdateInfo.fromGitHub(data, _currentVersion ?? '0.0.0');
        
        debugPrint('📦 GitHub latest version: ${updateInfo.latestVersion}');
        debugPrint('📱 Current version: ${updateInfo.currentVersion}');
        debugPrint('🔄 Update available: ${updateInfo.updateAvailable}');
        
        return updateInfo;
      } else if (response.statusCode == 404) {
        debugPrint('⚠️ No releases found on GitHub');
        return null;
      } else {
        debugPrint('❌ GitHub API error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error checking for updates: $e');
      return null;
    } finally {
      _isChecking = false;
    }
  }
  
  /// Descargar e instalar actualización
  static Future<bool> downloadAndInstall(
    String version, {
    String? downloadUrl,
    Function(double)? onProgress,
  }) async {
    if (_isDownloading) return false;
    
    try {
      _isDownloading = true;
      _downloadProgress = 0.0;
      
      // Determinar URL de descarga (usar la proporcionada o construir desde GitHub)
      final url = downloadUrl ?? 
        '${GitHubConfig.downloadUrl}/$version/Control_inventario_SMD_Setup.exe';
      
      // Obtener directorio de descargas
      final downloadsDir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final installerPath = '${downloadsDir.path}\\Control_inventario_SMD_Setup_$version.exe';
      
      debugPrint('📥 Downloading update from: $url');
      debugPrint('📁 Saving to: $installerPath');
      
      // Descargar archivo
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);
      
      if (response.statusCode != 200) {
        throw Exception('Download failed with status: ${response.statusCode}');
      }
      
      final contentLength = response.contentLength ?? 0;
      final file = File(installerPath);
      final sink = file.openWrite();
      
      int downloaded = 0;
      
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        
        if (contentLength > 0) {
          _downloadProgress = downloaded / contentLength;
          onProgress?.call(_downloadProgress);
        }
      }
      
      await sink.close();
      
      debugPrint('✅ Download complete: $installerPath');
      
      // Ejecutar instalador
      await _runInstaller(installerPath);
      
      return true;
    } catch (e) {
      debugPrint('❌ Error downloading update: $e');
      return false;
    } finally {
      _isDownloading = false;
      _downloadProgress = 0.0;
    }
  }
  
  /// Ejecutar el instalador
  static Future<void> _runInstaller(String installerPath) async {
    try {
      // Verificar que el archivo existe
      final file = File(installerPath);
      if (!await file.exists()) {
        throw Exception('Installer file not found');
      }
      
      // Ejecutar instalador
      await Process.start(installerPath, [], mode: ProcessStartMode.detached);
      
      debugPrint('🚀 Installer launched: $installerPath');
      
      // Cerrar la aplicación actual después de un breve delay
      await Future.delayed(const Duration(seconds: 2));
      exit(0);
    } catch (e) {
      debugPrint('❌ Error running installer: $e');
      
      // Intentar abrir la carpeta donde está el instalador
      try {
        final uri = Uri.file(File(installerPath).parent.path);
        await launchUrl(uri);
      } catch (_) {}
      
      rethrow;
    }
  }
  
  /// Abrir URL de descarga en el navegador
  static Future<void> openDownloadUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('❌ Error opening download URL: $e');
    }
  }
  
  /// Mostrar diálogo de actualización disponible
  static Future<void> showUpdateDialog(
    BuildContext context,
    UpdateInfo updateInfo, {
    bool canDismiss = true,
  }) async {
    final effectiveCanDismiss = canDismiss && !updateInfo.isMandatory;
    
    return showDialog(
      context: context,
      barrierDismissible: effectiveCanDismiss,
      builder: (context) => _UpdateDialog(
        updateInfo: updateInfo,
        canDismiss: effectiveCanDismiss,
      ),
    );
  }
  
  /// Verificar actualizaciones y mostrar diálogo si hay disponibles
  static Future<void> checkAndPrompt(
    BuildContext context, {
    bool showNoUpdateMessage = false,
  }) async {
    final updateInfo = await checkForUpdates();
    
    if (!context.mounted) return;
    
    if (updateInfo != null && updateInfo.updateAvailable) {
      await showUpdateDialog(context, updateInfo);
    } else if (showNoUpdateMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ya tienes la última versión (${currentVersion})'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

/// Widget de diálogo de actualización
class _UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final bool canDismiss;

  const _UpdateDialog({
    required this.updateInfo,
    required this.canDismiss,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.canDismiss && !_isDownloading,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.system_update, color: Colors.blue, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '¡Nueva Versión Disponible!',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Versiones
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Versión Actual', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          widget.updateInfo.currentVersion,
                          style: const TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Icon(Icons.arrow_forward, color: Colors.white38),
                    Column(
                      children: [
                        const Text('Nueva Versión', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          widget.updateInfo.latestVersion,
                          style: const TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Fecha de lanzamiento
              if (widget.updateInfo.releaseDate != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 14, color: Colors.white38),
                    const SizedBox(width: 8),
                    Text(
                      'Publicado: ${widget.updateInfo.releaseDate}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ],
              
              // Notas de la versión
              if (widget.updateInfo.releaseNotes != null && widget.updateInfo.releaseNotes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Novedades:',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.updateInfo.releaseNotes!,
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ),
                ),
              ],
              
              // Obligatorio
              if (widget.updateInfo.isMandatory) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Esta actualización es obligatoria para continuar usando la aplicación.',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              // Progreso de descarga
              if (_isDownloading) ...[
                const SizedBox(height: 16),
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Descargando... ${(_progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ],
              
              // Error
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (widget.canDismiss && !_isDownloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Más tarde', style: TextStyle(color: Colors.white54)),
            ),
          
          if (!_isDownloading)
            ElevatedButton.icon(
              onPressed: _downloadAndInstall,
              icon: const Icon(Icons.download),
              label: const Text('Descargar e Instalar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _error = null;
      _progress = 0.0;
    });

    try {
      final success = await UpdateService.downloadAndInstall(
        widget.updateInfo.latestVersion,
        downloadUrl: widget.updateInfo.downloadUrl,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
      );

      if (!success && mounted) {
        setState(() {
          _isDownloading = false;
          _error = 'Error al descargar la actualización. Intente abrir el enlace manualmente.';
        });
        
        // Si hay URL de descarga, ofrecerla como alternativa
        if (widget.updateInfo.downloadUrl != null) {
          await UpdateService.openDownloadUrl(widget.updateInfo.downloadUrl!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _error = 'Error: $e';
        });
      }
    }
  }
}

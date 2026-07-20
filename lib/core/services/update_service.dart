import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/server_config.dart';

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
    
    // Si la API no incluye assets, usar el nombre generado por build.ps1.
    // No usar html_url: guardaría una página HTML con extensión .exe.
    if (downloadUrl == null && tagName.isNotEmpty && latestVersion.isNotEmpty) {
      downloadUrl =
          '${GitHubConfig.downloadUrl}/$tagName/Control_inventario_SMD_Setup_v$latestVersion.exe';
    }
    
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

class _UpdateCheckAttempt {
  final String source;
  final UpdateInfo? info;
  final String? error;

  const _UpdateCheckAttempt({
    required this.source,
    this.info,
    this.error,
  });
}

/// Servicio para manejar actualizaciones de la aplicación
class UpdateService {
  static String? _currentVersion;
  static bool _isChecking = false;
  static bool _isDownloading = false;
  static double _downloadProgress = 0.0;
  static String? _lastCheckError;
  static String? _lastDownloadError;
  
  /// Versión actual de la aplicación
  static String get currentVersion => _currentVersion ?? '0.0.0';
  
  /// Indica si está verificando actualizaciones
  static bool get isChecking => _isChecking;
  
  /// Indica si está descargando una actualización
  static bool get isDownloading => _isDownloading;
  
  /// Progreso de descarga (0.0 - 1.0)
  static double get downloadProgress => _downloadProgress;

  /// Último error de verificación, listo para mostrar al usuario.
  static String? get lastCheckError => _lastCheckError;

  /// Último error de descarga o ejecución del instalador.
  static String? get lastDownloadError => _lastDownloadError;
  
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
  
  /// Verificar si hay actualizaciones disponibles.
  /// Consulta GitHub y el backend configurado en paralelo para que una red que
  /// bloquee api.github.com todavía pueda obtener la versión desde el servidor.
  static Future<UpdateInfo?> checkForUpdates() async {
    if (_isChecking) return null;

    try {
      _isChecking = true;
      _lastCheckError = null;

      if (_currentVersion == null) {
        await loadCurrentVersion();
      }

      final attempts = await Future.wait([
        _attemptUpdateCheck('GitHub', _checkGitHubApi),
        _attemptUpdateCheck('servidor ${ServerConfig.baseUrl}',
            _checkConfiguredServer),
      ]);

      // GitHub CONTROL-ROLLOS es la fuente autoritativa. El backend es una
      // tabla compartida y nunca debe reemplazar una respuesta válida de este
      // repositorio con la versión de otra aplicación.
      final githubAttempt = attempts.first;
      if (githubAttempt.info != null) {
        _logUpdateInfo(githubAttempt.source, githubAttempt.info!);
        return githubAttempt.info;
      }

      // api.github.com puede estar bloqueado aunque github.com funcione.
      final webAttempt = await _attemptUpdateCheck(
        'página de GitHub',
        _checkGitHubReleasePage,
      );
      if (webAttempt.info != null) {
        _logUpdateInfo(webAttempt.source, webAttempt.info!);
        return webAttempt.info;
      }

      // Si GitHub no fue accesible, aceptar la respuesta válida del backend.
      final serverAttempt = attempts[1];
      if (serverAttempt.info != null) {
        _logUpdateInfo(serverAttempt.source, serverAttempt.info!);
        return serverAttempt.info;
      }

      final errors = <String>[
        for (final attempt in [...attempts, webAttempt])
          if (attempt.error != null) '${attempt.source}: ${attempt.error}',
      ];
      _lastCheckError = errors.isEmpty
          ? 'No se recibió una respuesta válida de actualización.'
          : 'No se pudo consultar la actualización. ${errors.join(' | ')}';
      debugPrint('❌ $_lastCheckError');
      return null;
    } finally {
      _isChecking = false;
    }
  }

  static Future<_UpdateCheckAttempt> _attemptUpdateCheck(
    String source,
    Future<UpdateInfo> Function() action,
  ) async {
    try {
      return _UpdateCheckAttempt(source: source, info: await action());
    } catch (error) {
      final message = _friendlyNetworkError(error);
      debugPrint('⚠️ Update check failed ($source): $message');
      return _UpdateCheckAttempt(source: source, error: message);
    }
  }

  static Future<UpdateInfo> _checkGitHubApi() async {
    final response = await http.get(
      Uri.parse(GitHubConfig.apiUrl),
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'CONTROL-ROLLOS-App',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw HttpException('GitHub respondió HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> ||
        (data['tag_name']?.toString().isEmpty ?? true)) {
      throw const FormatException('GitHub devolvió una respuesta sin versión');
    }
    return UpdateInfo.fromGitHub(data, currentVersion);
  }

  static Future<UpdateInfo> _checkConfiguredServer() async {
    final uri = Uri.parse('${ServerConfig.baseUrl}/updates/check').replace(
      queryParameters: {
        'currentVersion': currentVersion,
        'app': 'control_inventario_smd',
      },
    );
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 7));

    if (response.statusCode != 200) {
      throw HttpException('el servidor respondió HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['success'] != true) {
      throw const FormatException('el servidor devolvió una respuesta inválida');
    }
    final info = UpdateInfo.fromJson(data);
    if (info.latestVersion.trim().isEmpty) {
      throw const FormatException(
        'el servidor no tiene versiones publicadas',
      );
    }
    final serverDownloadUrl = info.downloadUrl?.trim();
    if (serverDownloadUrl != null &&
        serverDownloadUrl.isNotEmpty &&
        !_isControlInventarioInstallerUrl(serverDownloadUrl)) {
      throw FormatException(
        'el servidor devolvió una actualización de otra aplicación: '
        '$serverDownloadUrl',
      );
    }
    if (!info.updateAvailable ||
        (serverDownloadUrl != null && serverDownloadUrl.isNotEmpty)) {
      return info;
    }

    final normalizedVersion = info.latestVersion.startsWith('v')
        ? info.latestVersion.substring(1)
        : info.latestVersion;
    return UpdateInfo(
      updateAvailable: info.updateAvailable,
      currentVersion: info.currentVersion,
      latestVersion: normalizedVersion,
      releaseDate: info.releaseDate,
      downloadUrl:
          '${GitHubConfig.downloadUrl}/v$normalizedVersion/Control_inventario_SMD_Setup_v$normalizedVersion.exe',
      releaseNotes: info.releaseNotes,
      isMandatory: info.isMandatory,
    );
  }

  static bool _isControlInventarioInstallerUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    final lowerPath = uri.path.toLowerCase();
    final hasExpectedInstaller =
        lowerPath.contains('control_inventario_smd_setup_v') &&
            lowerPath.endsWith('.exe');
    if (!hasExpectedInstaller) return false;

    if (uri.host.toLowerCase() == 'github.com') {
      return lowerPath.contains(
        '/${GitHubConfig.owner.toLowerCase()}/${GitHubConfig.repo.toLowerCase()}/releases/download/',
      );
    }
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  static Future<UpdateInfo> _checkGitHubReleasePage() async {
    final client = http.Client();
    try {
      final request = http.Request(
        'GET',
        Uri.parse(
          'https://github.com/${GitHubConfig.owner}/${GitHubConfig.repo}/releases/latest',
        ),
      )
        ..followRedirects = false
        ..headers['User-Agent'] = 'CONTROL-ROLLOS-App';
      final response = await client.send(request).timeout(
            const Duration(seconds: 10),
          );
      final location = response.headers['location'] ?? '';
      await response.stream.drain<void>();
      final match = RegExp(r'/releases/tag/([^/?#]+)').firstMatch(location);
      if (match == null) {
        throw const FormatException(
          'GitHub no indicó la versión más reciente',
        );
      }
      final tagName = Uri.decodeComponent(match.group(1)!);
      final latestVersion =
          tagName.startsWith('v') ? tagName.substring(1) : tagName;
      return UpdateInfo(
        updateAvailable:
            UpdateInfo._compareVersions(latestVersion, currentVersion) > 0,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl:
            '${GitHubConfig.downloadUrl}/$tagName/Control_inventario_SMD_Setup_v$latestVersion.exe',
        isMandatory: true,
      );
    } finally {
      client.close();
    }
  }

  static void _logUpdateInfo(String source, UpdateInfo info) {
    debugPrint('📦 Update source: $source');
    debugPrint('📦 Latest version: ${info.latestVersion}');
    debugPrint('📱 Current version: ${info.currentVersion}');
    debugPrint('🔄 Update available: ${info.updateAvailable}');
  }

  static String _friendlyNetworkError(Object error) {
    if (error is TimeoutException) return 'tiempo de espera agotado';
    if (error is SocketException) {
      return 'sin conexión o dominio bloqueado (${error.message})';
    }
    if (error is HandshakeException) {
      return 'certificado TLS rechazado por la PC o la red';
    }
    if (error is FormatException) return error.message;
    if (error is HttpException) return error.message;
    return error.toString();
  }
  
  /// Descargar e instalar actualización
  static Future<bool> downloadAndInstall(
    String version, {
    String? downloadUrl,
    Function(double)? onProgress,
  }) async {
    if (_isDownloading) return false;

    http.Client? client;
    IOSink? sink;
    File? partialFile;
    try {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _lastDownloadError = null;

      final normalizedVersion = version.startsWith('v')
          ? version.substring(1)
          : version;
      final tagName = version.startsWith('v') ? version : 'v$version';
      final url = (downloadUrl != null && downloadUrl.trim().isNotEmpty)
          ? downloadUrl.trim()
          : '${GitHubConfig.downloadUrl}/$tagName/Control_inventario_SMD_Setup_v$normalizedVersion.exe';

      // Usar TEMP evita carpetas Descargas redirigidas, OneDrive y protección
      // contra escritura que varían entre PCs.
      final tempDir = await getTemporaryDirectory();
      final updateDir = Directory(
        '${tempDir.path}\\control_inventario_smd_updates',
      );
      await updateDir.create(recursive: true);
      final installerPath =
          '${updateDir.path}\\Control_inventario_SMD_Setup_v$normalizedVersion.exe';
      partialFile = File('$installerPath.part');
      if (await partialFile.exists()) await partialFile.delete();

      debugPrint('📥 Downloading update from: $url');
      debugPrint('📁 Saving to: $installerPath');

      client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = 'CONTROL-ROLLOS-App';
      final response = await client.send(request).timeout(
            const Duration(seconds: 20),
          );

      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw HttpException(
          'la descarga respondió HTTP ${response.statusCode}',
        );
      }

      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.contains('text/html')) {
        await response.stream.drain<void>();
        throw const FormatException(
          'el enlace devolvió una página web en lugar del instalador',
        );
      }

      final contentLength = response.contentLength ?? 0;
      sink = partialFile.openWrite();
      int downloaded = 0;

      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        sink.add(chunk);
        downloaded += chunk.length;

        if (contentLength > 0) {
          _downloadProgress = downloaded / contentLength;
          onProgress?.call(_downloadProgress);
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (contentLength > 0 && downloaded != contentLength) {
        throw HttpException(
          'descarga incompleta: $downloaded de $contentLength bytes',
        );
      }
      if (downloaded < 1024 * 1024) {
        throw const FormatException(
          'el archivo descargado es demasiado pequeño para ser el instalador',
        );
      }

      final randomAccess = await partialFile.open();
      final signature = await randomAccess.read(2);
      await randomAccess.close();
      if (signature.length != 2 ||
          signature[0] != 0x4D ||
          signature[1] != 0x5A) {
        throw const FormatException(
          'el archivo descargado no es un ejecutable de Windows válido',
        );
      }

      final installer = File(installerPath);
      if (await installer.exists()) await installer.delete();
      await partialFile.rename(installerPath);
      partialFile = null;

      _downloadProgress = 1.0;
      onProgress?.call(_downloadProgress);
      debugPrint('✅ Download complete: $installerPath');
      await _runInstaller(installerPath);

      return true;
    } catch (e) {
      _lastDownloadError =
          'No se pudo descargar o abrir la actualización: ${_friendlyNetworkError(e)}';
      debugPrint('❌ Error downloading update: $e');
      return false;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client?.close();
      if (partialFile != null) {
        try {
          if (await partialFile.exists()) await partialFile.delete();
        } catch (_) {}
      }
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
    } else if (_lastCheckError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lastCheckError!),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 10),
        ),
      );
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
      canPop: (widget.canDismiss || _error != null) && !_isDownloading,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.2),
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
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.5)),
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
                    color: Colors.red.withValues(alpha: 0.2),
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
          if ((widget.canDismiss || _error != null) && !_isDownloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                _error == null ? 'Más tarde' : 'Continuar sin actualizar',
                style: const TextStyle(color: Colors.white54),
              ),
            ),

          if (_error != null &&
              widget.updateInfo.downloadUrl != null &&
              !_isDownloading)
            TextButton.icon(
              onPressed: () => UpdateService.openDownloadUrl(
                widget.updateInfo.downloadUrl!,
              ),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Abrir descarga manual'),
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
          _error = UpdateService.lastDownloadError ??
              'No se pudo descargar la actualización.';
        });
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

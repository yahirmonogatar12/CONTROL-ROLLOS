import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:smb_connect/smb_connect.dart';
import 'package:url_launcher/url_launcher.dart';

/// Configuración de GitHub (se conserva solo para UpdateInfo.fromGitHub / tests).
class GitHubConfig {
  static const String owner = 'yahirmonogatar12';
  static const String repo = 'CONTROL-ROLLOS';
  static const String apiUrl =
      'https://api.github.com/repos/$owner/$repo/releases/latest';
  static const String downloadUrl =
      'https://github.com/$owner/$repo/releases/download';
}

/// Carpeta de red del servidor donde se publica el último instalador de PC.
/// Solo hay que soltar ahí el .exe: Control_inventario_SMD_Setup_vX.Y.Z.exe
class UpdateShareConfig {
  static const String pcSharePath = r'\\192.168.1.10\updates\SMT\PC';
  static const String installerPrefix = 'Control_inventario_SMD_Setup_v';

  /// Variables esperadas en el archivo .env que acompaña al ejecutable.
  static const String usernameKey = 'UPDATE_SHARE_USERNAME';
  static const String passwordKey = 'UPDATE_SHARE_PASSWORD';
  static const String domainKey = 'UPDATE_SHARE_DOMAIN';

  /// `net use` solo acepta el servidor y el nombre del recurso compartido,
  /// no las subcarpetas que se usan para publicar los instaladores.
  static String get shareRoot {
    final parts = pcSharePath
        .replaceFirst(RegExp(r'^\\\\'), '')
        .split('\\')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) return pcSharePath;
    return '\\\\${parts[0]}\\${parts[1]}';
  }
}

/// En Android la ruta UNC se consume mediante SMB 2.x. `updates` es el recurso
/// compartido y `SMT/ANDROID` es la carpeta relativa dentro de ese recurso.
class AndroidUpdateShareConfig {
  static const String host = '192.168.1.10';
  static const String share = 'updates';
  static const String directory = 'SMT/ANDROID';
  static const String apkPrefix = 'Control_inventario_SMD_v';

  static String remotePath(String fileName) => '/$share/$directory/$fileName';

  static String downloadUrl(String fileName) =>
      'smb://$host/$share/$directory/${Uri.encodeComponent(fileName)}';
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
  factory UpdateInfo.fromGitHub(
      Map<String, dynamic> json, String currentVersion) {
    // Obtener tag_name (ej: "v1.2.0" o "1.2.0")
    String tagName = json['tag_name']?.toString() ?? '';
    // Remover prefijo 'v' si existe
    String latestVersion =
        tagName.startsWith('v') ? tagName.substring(1) : tagName;

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
      isMandatory:
          !isPrerelease && hasUpdate, // Obligatorio si no es pre-release
    );
  }

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    // Handle isMandatory as int (0/1) or bool
    final mandatory = json['isMandatory'];
    final isMandatoryBool =
        mandatory == true || mandatory == 1 || mandatory == '1';

    // Handle updateAvailable as int (0/1) or bool
    final available = json['updateAvailable'];
    final updateAvailableBool =
        available == true || available == 1 || available == '1';

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

class _UpdateShareCredentials {
  final String username;
  final String password;
  final String domain;

  const _UpdateShareCredentials({
    required this.username,
    required this.password,
    required this.domain,
  });

  String get windowsUsername => domain.isNotEmpty && !username.contains('@')
      ? '$domain\\$username'
      : username;
}

/// Servicio para manejar actualizaciones de la aplicación
class UpdateService {
  static String? _currentVersion;
  static bool _isChecking = false;
  static bool _isDownloading = false;
  static double _downloadProgress = 0.0;
  static String? _lastCheckError;
  static String? _lastDownloadError;
  static String? _lastAndroidApkPath;
  static String? _lastAndroidApkVersion;
  static const MethodChannel _androidUpdateChannel =
      MethodChannel('control_inventario_smd/app_update');

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
      final versionFileName =
          Platform.isAndroid ? 'VERSION_ANDROID.txt' : 'VERSION.txt';
      // En modo release, el VERSION.txt está en el directorio de la app
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;

      // Intentar diferentes ubicaciones
      final possiblePaths = [
        '$exeDir\\data\\flutter_assets\\assets\\$versionFileName',
        '$exeDir\\data\\flutter_assets\\$versionFileName',
        '$exeDir\\$versionFileName',
        'assets/$versionFileName',
        versionFileName,
      ];

      for (final path in possiblePaths) {
        final file = File(path);
        if (await file.exists()) {
          _currentVersion = (await file.readAsString()).trim();
          debugPrint('📱 App version loaded: $_currentVersion from $path');
          return;
        }
      }

      try {
        _currentVersion = (await rootBundle.loadString(versionFileName)).trim();
        debugPrint(
          '📱 App version loaded from Flutter asset $versionFileName: $_currentVersion',
        );
        return;
      } catch (_) {}

      // Si no se encuentra, usar versión por defecto
      _currentVersion = '1.0.0';
      debugPrint('⚠️ VERSION.txt not found, using default: $_currentVersion');
    } catch (e) {
      _currentVersion = '1.0.0';
      debugPrint('❌ Error loading version: $e');
    }
  }

  /// Verificar si hay actualizaciones disponibles en la carpeta de red del
  /// servidor (\\192.168.1.10\updates\SMT\PC). El instalador más nuevo que se
  /// haya colocado ahí es la fuente de verdad.
  static Future<UpdateInfo?> checkForUpdates() async {
    if (_isChecking) return null;

    try {
      _isChecking = true;
      _lastCheckError = null;

      if (_currentVersion == null) {
        await loadCurrentVersion();
      }

      final attempt = Platform.isAndroid
          ? await _attemptUpdateCheck(
              'servidor de actualizaciones Android',
              _checkAndroidNetworkShare,
            )
          : await _attemptUpdateCheck(
              'servidor de actualizaciones',
              _checkNetworkShare,
            );
      if (attempt.info != null) {
        _logUpdateInfo(attempt.source, attempt.info!);
        return attempt.info;
      }

      _lastCheckError =
          'No se pudo consultar la actualización. ${attempt.source}: ${attempt.error ?? 'sin respuesta'}';
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

  /// Lee la carpeta de red y arma el UpdateInfo con el instalador más nuevo.
  static Future<UpdateInfo> _checkNetworkShare() async {
    final dir = Directory(UpdateShareConfig.pcSharePath);
    await _ensureNetworkShareAccess(dir);
    if (!await dir.exists()) {
      throw const FileSystemException(
        'no se pudo acceder a la carpeta de actualizaciones del servidor',
      );
    }

    final fileNames = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        fileNames.add(entity.uri.pathSegments.last);
      }
    }

    final latest = pickLatestInstallerVersion(fileNames);
    if (latest == null) {
      throw const FormatException(
        'no hay instaladores en la carpeta de actualizaciones',
      );
    }

    final hasUpdate = UpdateInfo._compareVersions(latest, currentVersion) > 0;
    return UpdateInfo(
      updateAvailable: hasUpdate,
      currentVersion: currentVersion,
      latestVersion: latest,
      downloadUrl:
          '${UpdateShareConfig.pcSharePath}\\${UpdateShareConfig.installerPrefix}$latest.exe',
      isMandatory: hasUpdate,
    );
  }

  /// Consulta por SMB los APKs de \\192.168.1.10\updates\SMT\ANDROID.
  static Future<UpdateInfo> _checkAndroidNetworkShare() async {
    final connection = await _connectToAndroidUpdateShare();
    try {
      final folder = await connection.file(
        '/${AndroidUpdateShareConfig.share}/${AndroidUpdateShareConfig.directory}/',
      );
      final files = await connection.listFiles(folder);
      final apkFiles = files
          .where((file) =>
              file.isFile() && file.name.toLowerCase().endsWith('.apk'))
          .toList();
      final latest = pickLatestAndroidApk(
        apkFiles.map((file) => file.name),
      );
      if (latest == null) {
        throw const FormatException(
          'no hay APKs con versión en la carpeta de actualizaciones Android',
        );
      }

      final hasUpdate =
          UpdateInfo._compareVersions(latest.version, currentVersion) > 0;
      return UpdateInfo(
        updateAvailable: hasUpdate,
        currentVersion: currentVersion,
        latestVersion: latest.version,
        downloadUrl: AndroidUpdateShareConfig.downloadUrl(latest.fileName),
        isMandatory: false,
      );
    } finally {
      await connection.close();
    }
  }

  /// De una lista de nombres de archivo, regresa la versión más alta de un
  /// instalador Control_inventario_SMD_Setup_vX.Y.Z.exe, o null si no hay.
  /// Público para poder testear el parseo sin tocar el sistema de archivos.
  static String? pickLatestInstallerVersion(Iterable<String> fileNames) {
    final re = RegExp(
      '^${RegExp.escape(UpdateShareConfig.installerPrefix)}'
      r'(\d+(?:\.\d+)*)\.exe$',
      caseSensitive: false,
    );
    String? best;
    for (final name in fileNames) {
      final match = re.firstMatch(name.trim());
      if (match == null) continue;
      final version = match.group(1)!;
      if (best == null || UpdateInfo._compareVersions(version, best) > 0) {
        best = version;
      }
    }
    return best;
  }

  /// Acepta nombres como Control_inventario_SMD_v1.2.3.apk,
  /// app-release-1.2.3.apk o cualquier APK que termine con una versión.
  static ({String fileName, String version})? pickLatestAndroidApk(
    Iterable<String> fileNames,
  ) {
    final versionPattern = RegExp(
      r'(\d+(?:\.\d+){1,3})(?=[^0-9]*\.apk$)',
      caseSensitive: false,
    );
    ({String fileName, String version})? best;
    for (final rawName in fileNames) {
      final fileName = rawName.trim();
      final match = versionPattern.firstMatch(fileName);
      if (match == null) continue;
      final version = match.group(1)!;
      if (best == null ||
          UpdateInfo._compareVersions(version, best.version) > 0) {
        best = (fileName: fileName, version: version);
      }
    }
    return best;
  }

  /// Abre una sesión SMB para esta aplicación cuando Windows todavía no tiene
  /// credenciales válidas para el recurso compartido.
  ///
  /// El .env debe estar junto al ejecutable en producción o en el directorio
  /// actual durante desarrollo. No se agrega a `pubspec.yaml`: así no queda
  /// dentro de `flutter_assets`, y el archivo puede instalarse por separado.
  static Future<void> _ensureNetworkShareAccess(Directory dir) async {
    try {
      if (await dir.exists()) return;
    } on FileSystemException catch (error) {
      // En Windows, Directory.exists() puede lanzar 1326 cuando todavía no hay
      // una sesión SMB autenticada. Ese error debe activar el `net use` de
      // abajo, no impedir que se lean las credenciales del .env.
      debugPrint(
        '⚠️ El recurso SMB requiere autenticación: ${error.osError?.errorCode ?? 'sin código'}',
      );
    }
    if (!Platform.isWindows) return;

    final credentials = await _loadShareCredentials();
    if (credentials == null) return;

    final result = await Process.run(
      'net',
      [
        'use',
        UpdateShareConfig.shareRoot,
        credentials.password,
        '/user:${credentials.windowsUsername}',
        '/persistent:no',
      ],
      runInShell: false,
    );

    if (result.exitCode != 0) {
      // No incluir stdout/stderr porque algunos mensajes de `net use` pueden
      // contener información de la cuenta o de la red.
      throw const FileSystemException(
        'no se pudo autenticar la carpeta de actualizaciones con las credenciales del .env',
      );
    }
  }

  static Future<_UpdateShareCredentials?> _loadShareCredentials() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '$exeDir\\.env',
      '${Directory.current.path}\\.env',
    ];

    for (final path in candidates.toSet()) {
      final file = File(path);
      if (!await file.exists()) continue;

      final values = parseEnvContent(await file.readAsString());
      final credentials = _credentialsFromValues(values);
      if (credentials != null) return credentials;
    }

    // En Android no existe un archivo junto al ejecutable. El build incorpora
    // el mismo .env como asset para que el cliente SMB pueda autenticarse.
    if (Platform.isAndroid) {
      try {
        final values = parseEnvContent(await rootBundle.loadString('.env'));
        return _credentialsFromValues(values);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  static _UpdateShareCredentials? _credentialsFromValues(
    Map<String, String> values,
  ) {
    var username = values[UpdateShareConfig.usernameKey]?.trim();
    final password = values[UpdateShareConfig.passwordKey];
    var domain = values[UpdateShareConfig.domainKey]?.trim() ?? '';
    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }

    final separator = username.indexOf('\\');
    if (separator > 0 && separator < username.length - 1) {
      if (domain.isEmpty) domain = username.substring(0, separator);
      username = username.substring(separator + 1);
    }

    return _UpdateShareCredentials(
      username: username,
      password: password,
      domain: domain,
    );
  }

  static Future<SmbConnect> _connectToAndroidUpdateShare() async {
    final credentials = await _loadShareCredentials();
    if (credentials == null) {
      throw const FileSystemException(
        'faltan las credenciales SMB de actualizaciones en el .env del APK',
      );
    }

    return SmbConnect.connectAuth(
      host: AndroidUpdateShareConfig.host,
      username: credentials.username,
      password: credentials.password,
      domain: credentials.domain,
    ).timeout(const Duration(seconds: 15));
  }

  /// Parser pequeño para no agregar otra dependencia solo para leer `.env`.
  /// Se conservan espacios y `#` dentro del valor de la contraseña.
  static Map<String, String> parseEnvContent(String content) {
    final values = <String, String>{};
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final separator = line.indexOf('=');
      if (separator <= 0) continue;

      final key = line.substring(0, separator).trim();
      var value = line.substring(separator + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      values[key] = value;
    }
    return values;
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
    if (Platform.isAndroid) {
      return _downloadAndInstallAndroidApk(
        version,
        downloadUrl: downloadUrl,
        onProgress: onProgress,
      );
    }

    http.Client? client;
    IOSink? sink;
    File? partialFile;
    try {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _lastDownloadError = null;

      final normalizedVersion =
          version.startsWith('v') ? version.substring(1) : version;
      final url = (downloadUrl != null && downloadUrl.trim().isNotEmpty)
          ? downloadUrl.trim()
          : '${UpdateShareConfig.pcSharePath}\\${UpdateShareConfig.installerPrefix}$normalizedVersion.exe';

      // La fuente normal es la carpeta de red (ruta UNC): se copia el
      // instalador desde ahí. El bloque HTTP de abajo queda como respaldo.
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        return await _installFromLocalPath(url, normalizedVersion, onProgress);
      }

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

  static Future<bool> _downloadAndInstallAndroidApk(
    String version, {
    String? downloadUrl,
    Function(double)? onProgress,
  }) async {
    File? partialFile;
    IOSink? sink;
    SmbConnect? connection;
    try {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _lastDownloadError = null;

      final normalizedVersion =
          version.startsWith('v') ? version.substring(1) : version;
      final remoteFileName = _androidApkFileName(
        downloadUrl,
        normalizedVersion,
      );
      final downloadsDir =
          await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final generatedApkPath =
          '${downloadsDir.path}${Platform.pathSeparator}Control_inventario_SMD_$normalizedVersion.apk';
      final shouldReuseDownloadedApk =
          _lastAndroidApkVersion == normalizedVersion &&
              _lastAndroidApkPath != null;
      final apkPath =
          shouldReuseDownloadedApk ? _lastAndroidApkPath! : generatedApkPath;
      final apkFile = File(apkPath);

      if (shouldReuseDownloadedApk &&
          await apkFile.exists() &&
          await apkFile.length() >= 1024 * 1024) {
        _downloadProgress = 1.0;
        onProgress?.call(1.0);
        debugPrint('📦 Reintentando APK ya descargado: $apkPath');
      } else {
        partialFile = File('$apkPath.part');
        if (await partialFile.exists()) await partialFile.delete();

        connection = await _connectToAndroidUpdateShare();
        final remoteFile = await connection.file(
          AndroidUpdateShareConfig.remotePath(remoteFileName),
        );
        final stream = await connection.openRead(remoteFile);
        sink = partialFile.openWrite();
        final totalBytes = remoteFile.size;
        var downloadedBytes = 0;

        await for (final chunk in stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          if (totalBytes > 0) {
            _downloadProgress = downloadedBytes / totalBytes;
            onProgress?.call(_downloadProgress);
          }
        }

        await sink.flush();
        await sink.close();
        sink = null;

        if (downloadedBytes < 1024 * 1024) {
          throw const FormatException(
            'el APK copiado es demasiado pequeño o está incompleto',
          );
        }
        if (totalBytes > 0 && downloadedBytes != totalBytes) {
          throw FileSystemException(
            'copia SMB incompleta: $downloadedBytes de $totalBytes bytes',
          );
        }

        final randomAccess = await partialFile.open();
        final signature = await randomAccess.read(2);
        await randomAccess.close();
        if (signature.length != 2 ||
            signature[0] != 0x50 ||
            signature[1] != 0x4B) {
          throw const FormatException(
            'el archivo del servidor no es un APK válido',
          );
        }

        if (await apkFile.exists()) await apkFile.delete();
        await partialFile.rename(apkPath);
        partialFile = null;
        _lastAndroidApkPath = apkPath;
        _lastAndroidApkVersion = normalizedVersion;
        _downloadProgress = 1.0;
        onProgress?.call(1.0);
      }

      final installResult = await _openAndroidApkInstaller(apkPath);
      if (installResult == 'opened') return true;
      if (installResult == 'permissionRequired') {
        _lastDownloadError =
            'Activa "Permitir de esta fuente" y presiona Descargar e Instalar otra vez. El APK ya quedó descargado.';
      } else {
        _lastDownloadError ??= 'Android no pudo abrir el instalador del APK.';
      }
      return false;
    } catch (error) {
      _lastDownloadError =
          'No se pudo descargar o abrir el APK: ${_friendlyNetworkError(error)}';
      debugPrint('❌ Error updating Android from SMB: $error');
      return false;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        await connection?.close();
      } catch (_) {}
      if (partialFile != null) {
        try {
          if (await partialFile.exists()) await partialFile.delete();
        } catch (_) {}
      }
      _isDownloading = false;
      _downloadProgress = 0.0;
    }
  }

  static String _androidApkFileName(
    String? downloadUrl,
    String normalizedVersion,
  ) {
    if (downloadUrl != null && downloadUrl.trim().isNotEmpty) {
      final uri = Uri.tryParse(downloadUrl.trim());
      if (uri != null && uri.pathSegments.isNotEmpty) {
        final fileName = Uri.decodeComponent(uri.pathSegments.last);
        if (fileName.toLowerCase().endsWith('.apk')) return fileName;
      }
    }
    return '${AndroidUpdateShareConfig.apkPrefix}$normalizedVersion.apk';
  }

  static Future<String?> _openAndroidApkInstaller(String apkPath) async {
    try {
      return await _androidUpdateChannel.invokeMethod<String>(
        'installApk',
        {'path': apkPath},
      );
    } on PlatformException catch (error) {
      debugPrint(
        '⚠️ Android APK installer failed: ${error.code} ${error.message}',
      );
      _lastDownloadError = error.message;
      return null;
    } on MissingPluginException catch (error) {
      debugPrint('⚠️ Android APK installer channel missing: $error');
      _lastDownloadError =
          'Esta APK todavía no incluye el instalador interno. Instala manualmente esta versión una vez.';
      return null;
    }
  }

  /// Copia el instalador desde la carpeta de red (ruta UNC/local) a TEMP y lo
  /// ejecuta. Correr desde TEMP evita bloqueos y advertencias de ejecutar un
  /// .exe directamente desde un recurso de red.
  static Future<bool> _installFromLocalPath(
    String sourcePath,
    String normalizedVersion,
    Function(double)? onProgress,
  ) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      _lastDownloadError =
          'No se encontró el instalador en el servidor: $sourcePath';
      return false;
    }

    final tempDir = await getTemporaryDirectory();
    final updateDir = Directory(
      '${tempDir.path}\\control_inventario_smd_updates',
    );
    await updateDir.create(recursive: true);
    final installerPath =
        '${updateDir.path}\\Control_inventario_SMD_Setup_v$normalizedVersion.exe';

    final dest = File(installerPath);
    if (await dest.exists()) await dest.delete();
    await source.copy(installerPath);

    if (await dest.length() < 1024 * 1024) {
      _lastDownloadError =
          'El instalador copiado es demasiado pequeño; ¿copia incompleta?';
      return false;
    }

    _downloadProgress = 1.0;
    onProgress?.call(1.0);
    debugPrint('✅ Instalador copiado desde red: $installerPath');
    await _runInstaller(installerPath);
    return true;
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

  static bool canOpenDownloadUrl(String? url) {
    final normalized = url?.trim().toLowerCase() ?? '';
    return normalized.startsWith('http://') ||
        normalized.startsWith('https://');
  }

  /// Mostrar diálogo de actualización disponible
  static Future<void> showUpdateDialog(
    BuildContext context,
    UpdateInfo updateInfo, {
    bool canDismiss = true,
    bool enforceMandatory = true,
  }) async {
    final effectiveCanDismiss =
        canDismiss && (!enforceMandatory || !updateInfo.isMandatory);

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
              child:
                  const Icon(Icons.system_update, color: Colors.blue, size: 28),
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
                        const Text('Versión Actual',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          widget.updateInfo.currentVersion,
                          style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Icon(Icons.arrow_forward, color: Colors.white38),
                    Column(
                      children: [
                        const Text('Nueva Versión',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          widget.updateInfo.latestVersion,
                          style: const TextStyle(
                              color: Colors.green,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
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
                    const Icon(Icons.calendar_today,
                        size: 14, color: Colors.white38),
                    const SizedBox(width: 8),
                    Text(
                      'Publicado: ${widget.updateInfo.releaseDate}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ],

              // Notas de la versión
              if (widget.updateInfo.releaseNotes != null &&
                  widget.updateInfo.releaseNotes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Novedades:',
                  style: TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.bold),
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
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ),
                ),
              ],

              // Obligatorio
              if (!widget.canDismiss && widget.updateInfo.isMandatory) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Descargando... ${(_progress * 100).toStringAsFixed(0)}%',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
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
                          style:
                              const TextStyle(color: Colors.red, fontSize: 12),
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
              UpdateService.canOpenDownloadUrl(widget.updateInfo.downloadUrl) &&
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

import 'dart:io';
import 'package:flutter/material.dart';
import '../services/backend_service.dart';
import '../theme/app_colors.dart';

/// Pantalla de carga inicial que:
/// - Muestra una animación de logo pulsante
/// - Inicia el backend automáticamente
/// - Espera a que el servidor esté listo
/// - Muestra progreso de conexión
/// - Permite reintentar en caso de error
/// 
/// Uso:
/// ```dart
/// LauncherScreen(
///   onReady: () => Navigator.pushReplacement(...),
/// )
/// ```
class LauncherScreen extends StatefulWidget {
  /// Callback cuando el backend está listo
  final VoidCallback onReady;
  
  /// Título de la aplicación (opcional)
  final String? appTitle;
  
  /// Subtítulo (opcional)
  final String? appSubtitle;
  
  /// Ruta del logo (opcional, default: 'assets/logo.png')
  final String logoPath;
  
  /// Tiempo mínimo de animación en segundos
  final int minimumAnimationSeconds;

  const LauncherScreen({
    super.key,
    required this.onReady,
    this.appTitle,
    this.appSubtitle,
    this.logoPath = 'assets/logo.png',
    this.minimumAnimationSeconds = 2,
  });

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> with SingleTickerProviderStateMixin {
  String _statusMessage = 'Iniciando...';
  double _progress = 0.0;
  bool _hasError = false;
  bool _isInitialized = false;
  String _version = '';
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    // Cargar la versión
    _loadVersion();
    
    // Esperar a que el widget esté completamente construido
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _initializeBackend();
      }
    });
  }

  Future<void> _loadVersion() async {
    String version = '1.0.0';
    
    try {
      // Intentar leer VERSION.txt del directorio del ejecutable
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final versionFile = File('$exeDir${Platform.pathSeparator}VERSION.txt');
      
      if (await versionFile.exists()) {
        version = (await versionFile.readAsString()).trim();
      } else {
        // Intentar leer del directorio actual (desarrollo)
        final devVersionFile = File('VERSION.txt');
        if (await devVersionFile.exists()) {
          version = (await devVersionFile.readAsString()).trim();
        }
      }
    } catch (e) {
      debugPrint('Error leyendo VERSION.txt: $e');
    }
    
    if (mounted) {
      setState(() {
        _version = version;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeBackend() async {
    // Tiempo mínimo de animación
    final startTime = DateTime.now();
    
    // Pequeño delay para asegurar que la UI esté visible
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (!mounted) return;
    
    setState(() {
      _statusMessage = 'Verificando servidor...';
      _progress = 0.1;
    });

    // Primero verificar si el backend ya está corriendo
    final alreadyRunning = await BackendService.isBackendAlreadyRunning();
    
    if (alreadyRunning) {
      if (!mounted) return;
      setState(() {
        _statusMessage = '¡Servidor detectado!';
        _progress = 1.0;
      });
      // Esperar el tiempo mínimo restante
      await _waitMinimumTime(startTime);
      if (mounted) widget.onReady();
      return;
    }

    // Si no está corriendo, intentar iniciarlo
    if (!mounted) return;
    setState(() {
      _statusMessage = 'Iniciando servidor backend...';
      _progress = 0.2;
    });

    final started = await BackendService.startBackend();
    
    if (!started) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Error: No se pudo iniciar el servidor.\nVerifique la configuración.';
        _hasError = true;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _statusMessage = 'Esperando que el servidor esté listo...';
      _progress = 0.3;
    });

    // Esperar a que el backend esté listo
    final ready = await BackendService.waitForBackend(
      onProgress: (message, progress) {
        if (mounted) {
          setState(() {
            _statusMessage = message;
            _progress = 0.3 + (progress * 0.7);
          });
        }
      },
    );

    if (ready) {
      await _waitMinimumTime(startTime);
      if (mounted) widget.onReady();
    } else {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Error: El servidor no respondió.\nVerifique la conexión a la base de datos.';
        _hasError = true;
      });
    }
  }

  Future<void> _waitMinimumTime(DateTime startTime) async {
    final elapsed = DateTime.now().difference(startTime);
    final minimumDuration = Duration(seconds: widget.minimumAnimationSeconds);
    final remaining = minimumDuration - elapsed;
    if (remaining.inMilliseconds > 0) {
      await Future.delayed(remaining);
    }
  }

  Future<void> _retry() async {
    setState(() {
      _hasError = false;
      _progress = 0.0;
    });
    await _initializeBackend();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1E2C),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo animado
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _hasError ? 1.0 : _pulseAnimation.value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: _hasError
                          ? []
                          : [
                              BoxShadow(
                                color: AppColors.headerTab.withOpacity(0.3),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        widget.logoPath,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              color: AppColors.gridHeader,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              _hasError ? Icons.error_outline : Icons.rocket_launch,
                              size: 60,
                              color: _hasError ? Colors.red : Colors.white70,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            
            // Título
            if (widget.appTitle != null)
              Text(
                widget.appTitle!,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            if (widget.appSubtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.appSubtitle!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
            const SizedBox(height: 50),
            
            // Barra de progreso
            if (!_hasError) ...[
              SizedBox(
                width: 300,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 8,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.headerTab,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Mensaje de error
            if (_hasError) ...[
              Container(
                width: 350,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Reintentar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.headerTab,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () {
                            widget.onReady();
                          },
                          child: const Text(
                            'Continuar sin servidor',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 60),
            
            // Footer con versión
            Text(
              'v$_version',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.3),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

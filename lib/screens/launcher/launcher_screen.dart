import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_warehousing_flutter/core/services/backend_service.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

class LauncherScreen extends StatefulWidget {
  final VoidCallback onReady;

  const LauncherScreen({super.key, required this.onReady});

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
      final versionFile = File('$exeDir\\VERSION.txt');
      
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
      // Si falla, usar versión por defecto
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
    // Tiempo mínimo de animación (2 segundos)
    final minimumDisplayTime = Future.delayed(const Duration(seconds: 2));
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
      await minimumDisplayTime;
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
        _statusMessage = 'Error: No se pudo iniciar el servidor.\nVerifique que Node.js esté instalado.';
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
            _progress = 0.3 + (progress * 0.7); // 30% a 100%
          });
        }
      },
    );

    if (ready) {
      // Calcular tiempo restante para completar los 2 segundos mínimos
      final elapsed = DateTime.now().difference(startTime);
      final remaining = const Duration(seconds: 2) - elapsed;
      if (remaining.inMilliseconds > 0) {
        await Future.delayed(remaining);
      }
      if (mounted) widget.onReady();
    } else {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Error: El servidor no respondió.\nVerifique la conexión a la base de datos.';
        _hasError = true;
      });
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
                        'assets/logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              color: AppColors.gridHeader,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              _hasError ? Icons.error_outline : Icons.inventory_2,
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
            const Text(
              'Control de Rollos',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Control inventario SMD',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
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
                            // Continuar sin backend (modo offline o para debug)
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

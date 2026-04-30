import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../config/server_config.dart';
import '../services/fcm_service.dart';
import '../services/server_discovery_service.dart';

/// Widget para mostrar y configurar el servidor activo
/// Se usa en la pantalla de login
class ServerConfigWidget extends StatefulWidget {
  final VoidCallback? onServerChanged;

  const ServerConfigWidget({
    super.key,
    this.onServerChanged,
  });

  @override
  State<ServerConfigWidget> createState() => _ServerConfigWidgetState();
}

class _ServerConfigWidgetState extends State<ServerConfigWidget> {
  bool _isExpanded = false;
  bool _isTestingConnection = false;
  bool? _connectionStatus;

  bool _isMobileLocalhost(ServerProfile? server) {
    if (!Platform.isAndroid || server == null) return false;
    final ip = server.ip.trim().toLowerCase();
    return ip == 'localhost' || ip == '127.0.0.1' || ip == '0.0.0.0';
  }

  Color _getFcmStatusColor(FCMConnectionStatus status) {
    if (!status.isSupported) return Colors.white54;
    if (status.isChecking) return Colors.amber;
    if (status.isActive) return Colors.green;
    if (status.lastError != null ||
        status.backendRegistered == false ||
        (status.topicSubscribed == false && !status.topicManagedByBackend)) {
      return Colors.orangeAccent;
    }
    if (status.hasToken || status.permissionStatus != null) {
      return Colors.blueAccent;
    }
    return Colors.white54;
  }

  IconData _getFcmStatusIcon(FCMConnectionStatus status) {
    if (!status.isSupported) return Icons.notifications_off_outlined;
    if (status.isChecking) return Icons.sync;
    if (status.isActive) return Icons.cloud_done_outlined;
    if (status.lastError != null ||
        status.backendRegistered == false ||
        (status.topicSubscribed == false && !status.topicManagedByBackend)) {
      return Icons.cloud_off_outlined;
    }
    return Icons.notifications_active_outlined;
  }

  String _getFcmStatusTitle(FCMConnectionStatus status) {
    if (!status.isSupported) return 'FCM no disponible en esta plataforma';
    if (status.isChecking) return 'Conectando FCM...';
    if (status.isActive) return 'FCM activo en este dispositivo';
    if (status.permissionStatus == AuthorizationStatus.denied) {
      return 'Permiso FCM denegado';
    }
    if (status.backendRegistered == false) {
      return 'Token sin registrar en backend';
    }
    if (status.topicManagedByBackend) {
      return 'FCM activo por backend';
    }
    if (status.topicSubscribed == false) {
      return 'Topic FCM sin suscripcion';
    }
    if (status.hasToken) {
      return 'FCM parcialmente configurado';
    }
    return 'FCM pendiente de conexion';
  }

  Widget _buildFcmStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeServer = ServerConfig.activeServer;
    final isMobileLocalhost = _isMobileLocalhost(activeServer);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252A3C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isMobileLocalhost
              ? Colors.amber.withOpacity(0.7)
              : _connectionStatus == true
                  ? Colors.green.withOpacity(0.5)
                  : _connectionStatus == false
                      ? Colors.red.withOpacity(0.5)
                      : Colors.white24,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header - siempre visible
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.dns_outlined,
                    color: isMobileLocalhost
                        ? Colors.amber
                        : _connectionStatus == true
                            ? Colors.green
                            : _connectionStatus == false
                                ? Colors.red
                                : Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Servidor: ${activeServer?.name ?? "No configurado"}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          activeServer != null
                              ? '${activeServer.ip}:${activeServer.port}'
                              : 'Tap para configurar',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Test connection button
                  if (_isTestingConnection)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white70),
                      ),
                    )
                  else
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        color: Colors.white.withOpacity(0.7),
                        size: 20,
                      ),
                      onPressed: _testConnection,
                      tooltip: 'Probar conexión',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),

          // Expanded content - server list
          if (_isExpanded) ...[
            const Divider(color: Colors.white24, height: 1),
            if (isMobileLocalhost)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.amber.withOpacity(0.08),
                child: const Text(
                  'Advertencia: en Android, "localhost" es el mismo telefono/emulador. Configure la IP de la PC del backend o use "Buscar servidores en red".',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            _buildServerList(),
            const Divider(color: Colors.white24, height: 1),
            _buildAddServerButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildServerList() {
    final servers = ServerConfig.servers;

    if (servers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No hay servidores configurados',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final server = servers[index];
        final isActive = server.id == ServerConfig.activeServer?.id;

        return ListTile(
          dense: true,
          leading: Icon(
            isActive ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isActive ? Colors.green : Colors.white54,
            size: 20,
          ),
          title: Text(
            server.name,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white70,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            '${server.protocol}://${server.ip}:${server.port}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Edit button
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                color: Colors.white54,
                onPressed: () => _showEditServerDialog(server),
                tooltip: 'Editar',
              ),
              // Delete button (no mostrar para el servidor activo si solo hay uno)
              if (servers.length > 1 || !isActive)
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  color: Colors.red.withOpacity(0.7),
                  onPressed: () => _confirmDeleteServer(server),
                  tooltip: 'Eliminar',
                ),
            ],
          ),
          onTap: isActive ? null : () => _selectServer(server),
        );
      },
    );
  }

  Widget _buildAddServerButton() {
    return Column(
      children: [
        // Botón buscar servidores en red (solo en Android)
        if (Platform.isAndroid)
          TextButton.icon(
            onPressed: _showDiscoveryDialog,
            icon: const Icon(Icons.wifi_find, size: 18),
            label: const Text('Buscar servidores en red'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue.shade300,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        TextButton.icon(
          onPressed: _showAddServerDialog,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Agregar servidor manual'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white70,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _showDiscoveryDialog() async {
    final discoveryService = ServerDiscoveryService();
    List<DiscoveredServer> foundServers = [];
    bool isScanning = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Iniciar escaneo
          if (isScanning && foundServers.isEmpty) {
            discoveryService
                .scanForServers(
              timeout: const Duration(seconds: 6),
            )
                .then((servers) {
              setDialogState(() {
                foundServers = servers;
                isScanning = false;
              });
            });
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1A1E2C),
            title: Row(
              children: [
                Icon(
                  isScanning ? Icons.wifi_find : Icons.dns,
                  color: Colors.blue.shade300,
                ),
                const SizedBox(width: 12),
                Text(
                  isScanning
                      ? 'Buscando servidores...'
                      : 'Servidores encontrados',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isScanning) ...[
                    const SizedBox(height: 20),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      'Escaneando red local...',
                      style: TextStyle(color: Colors.white.withOpacity(0.7)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Asegúrate de estar conectado a la misma red WiFi que el servidor',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ] else if (foundServers.isEmpty) ...[
                    const Icon(
                      Icons.search_off,
                      size: 48,
                      color: Colors.white38,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No se encontraron servidores',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Verifica que el servidor esté ejecutándose y conectado a la misma red',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    ListView.builder(
                      shrinkWrap: true,
                      itemCount: foundServers.length,
                      itemBuilder: (context, index) {
                        final server = foundServers[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.computer,
                            color: Colors.green,
                          ),
                          title: Text(
                            server.displayName,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            '${server.ip}:${server.port}',
                            style: const TextStyle(color: Colors.white54),
                          ),
                          trailing: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.blue,
                          ),
                          onTap: () async {
                            // Agregar servidor descubierto
                            final newServer = ServerProfile(
                              id: DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString(),
                              name: server.displayName,
                              ip: server.ip,
                              port: server.port,
                            );
                            await ServerConfig.addServer(newServer);
                            await ServerConfig.setActiveServer(newServer.id);

                            if (mounted) {
                              Navigator.pop(dialogContext);
                              setState(() => _connectionStatus = null);
                              widget.onServerChanged?.call();

                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Servidor "${server.displayName}" agregado'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (!isScanning)
                TextButton.icon(
                  onPressed: () {
                    setDialogState(() {
                      isScanning = true;
                      foundServers = [];
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Buscar de nuevo'),
                ),
              TextButton(
                onPressed: () {
                  discoveryService.dispose();
                  Navigator.pop(dialogContext);
                },
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _testConnection() async {
    final activeServer = ServerConfig.activeServer;
    if (_isMobileLocalhost(activeServer)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'En Android, localhost no apunta a la PC. Use la IP del servidor o la busqueda en red.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _connectionStatus = null;
    });

    final success = await ServerConfig.testActiveConnection();

    setState(() {
      _isTestingConnection = false;
      _connectionStatus = success;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Conexión exitosa al servidor'
                : 'No se pudo conectar al servidor',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _selectServer(ServerProfile server) async {
    await ServerConfig.setActiveServer(server.id);
    setState(() {
      _connectionStatus = null;
    });
    widget.onServerChanged?.call();
  }

  void _showAddServerDialog() {
    _showServerDialog(null);
  }

  void _showEditServerDialog(ServerProfile server) {
    _showServerDialog(server);
  }

  void _showServerDialog(ServerProfile? existingServer) {
    final nameController =
        TextEditingController(text: existingServer?.name ?? '');
    final ipController = TextEditingController(text: existingServer?.ip ?? '');
    final portController =
        TextEditingController(text: existingServer?.port.toString() ?? '3010');
    final centralHostController = TextEditingController();
    final centralPortController = TextEditingController(text: '4000');
    bool useHttps = existingServer?.useHttps ?? false;
    bool centralUseHttps = false;
    bool isEditing = existingServer != null;
    bool isLoadingFcmConfig = isEditing;
    bool didRequestFcmConfig = false;
    bool isSaving = false;
    bool isConnectingDeviceFcm = false;
    String? fcmConfigMessage;
    bool? fcmConfigSuccess;
    String? deviceFcmMessage;
    FCMConnectionStatus deviceFcmStatus = FCMService.instance.status;

    ServerProfile buildDraftServer() {
      final draftName = nameController.text.trim().isEmpty
          ? (existingServer?.name ?? 'Servidor')
          : nameController.text.trim();
      final draftIp = ipController.text.trim().isEmpty
          ? (existingServer?.ip ?? 'localhost')
          : ipController.text.trim();
      final draftPort = int.tryParse(portController.text.trim()) ??
          existingServer?.port ??
          3010;

      return ServerProfile(
        id: existingServer?.id ?? 'dialog-preview',
        name: draftName,
        ip: draftIp,
        port: draftPort,
        useHttps: useHttps,
        isActive: existingServer?.isActive ?? false,
        lastConnected: existingServer?.lastConnected,
      );
    }

    Future<void> loadFcmConfig(StateSetter setDialogState) async {
      if (existingServer == null) {
        setDialogState(() {
          isLoadingFcmConfig = false;
        });
        return;
      }

      final result = await ServerConfig.getSmtRequestsConfig(existingServer);
      if (!mounted) return;

      setDialogState(() {
        isLoadingFcmConfig = false;
        fcmConfigSuccess = result['success'] == true;

        if (result['success'] == true) {
          final config =
              (result['config'] as Map?)?.cast<String, dynamic>() ?? {};
          centralHostController.text = (config['centralHost'] ?? '').toString();
          centralPortController.text =
              (config['centralPort'] ?? 4000).toString();
          centralUseHttps = config['centralUseHttps'] == true;
          fcmConfigMessage = 'Configuracion FCM cargada desde el backend';
        } else {
          final errorText = result['error']?.toString() ??
              'No se pudo cargar la configuracion FCM';
          fcmConfigMessage = errorText.contains('no expone GET')
              ? '$errorText Puedes capturar los datos manualmente y guardarlos.'
              : errorText;
        }
      });
    }

    Future<void> connectDeviceFcm(StateSetter setDialogState) async {
      final ip = ipController.text.trim();
      final centralHost = centralHostController.text.trim();
      final centralPort =
          int.tryParse(centralPortController.text.trim()) ?? 4000;

      if (ip.isEmpty) {
        setDialogState(() {
          deviceFcmMessage = 'Primero captura la IP o hostname del backend';
        });
        return;
      }

      if (centralHost.isEmpty) {
        setDialogState(() {
          deviceFcmMessage =
              'Primero captura la IP o hostname central para FCM';
        });
        return;
      }

      setDialogState(() {
        isConnectingDeviceFcm = true;
        deviceFcmMessage = 'Guardando central y conectando FCM...';
      });

      final draftServer = buildDraftServer();
      final configResult = await ServerConfig.updateSmtRequestsConfig(
        draftServer,
        centralHost: centralHost,
        centralPort: centralPort,
        centralUseHttps: centralUseHttps,
      );

      if (!mounted) return;

      if (configResult['success'] != true) {
        setDialogState(() {
          isConnectingDeviceFcm = false;
          deviceFcmMessage =
              'No se pudo guardar el central: ${configResult['error'] ?? 'error desconocido'}';
        });
        return;
      }

      final refreshedStatus = await FCMService.instance.init(
        serverOverride: draftServer,
      );
      if (!mounted) return;

      setDialogState(() {
        isConnectingDeviceFcm = false;
        deviceFcmStatus = refreshedStatus;
        deviceFcmMessage = refreshedStatus.isActive
            ? 'FCM activo. Central guardado y token validado.'
            : (refreshedStatus.lastError ??
                refreshedStatus.backendMessage ??
                refreshedStatus.topicMessage ??
                'FCM verificado con advertencias');
        fcmConfigSuccess = true;
        fcmConfigMessage = 'Configuracion FCM guardada en el backend';
      });
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (isEditing && !didRequestFcmConfig) {
            didRequestFcmConfig = true;
            Future.microtask(() => loadFcmConfig(setDialogState));
          } else if (!isEditing && !didRequestFcmConfig) {
            didRequestFcmConfig = true;
            isLoadingFcmConfig = false;
          }

          final fcmStateColor = _getFcmStatusColor(deviceFcmStatus);
          final fcmStateIcon = _getFcmStatusIcon(deviceFcmStatus);
          final fcmStateTitle = _getFcmStatusTitle(deviceFcmStatus);

          return AlertDialog(
            backgroundColor: const Color(0xFF1A1E2C),
            title: Text(
              isEditing ? 'Editar servidor' : 'Agregar servidor',
              style: const TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      labelStyle: TextStyle(color: Colors.white70),
                      hintText: 'Ej: Producción, Desarrollo',
                      hintStyle: TextStyle(color: Colors.white38),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ipController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'IP o Hostname',
                      labelStyle: TextStyle(color: Colors.white70),
                      hintText: 'Ej: 192.168.1.100 o mi-servidor.com',
                      hintStyle: TextStyle(color: Colors.white38),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: portController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Puerto',
                      labelStyle: TextStyle(color: Colors.white70),
                      hintText: '3010',
                      hintStyle: TextStyle(color: Colors.white38),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 20),
                  // HTTPS Switch
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: useHttps
                            ? Colors.green.withValues(alpha: 0.5)
                            : Colors.white24,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          useHttps ? Icons.lock : Icons.lock_open,
                          color: useHttps ? Colors.green : Colors.white54,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Usar HTTPS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                useHttps
                                    ? 'Conexión segura (SSL/TLS)'
                                    : 'Conexión sin cifrar',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: useHttps,
                          onChanged: (value) {
                            setDialogState(() {
                              useHttps = value;
                              // Sugerir puerto 443 para HTTPS
                              if (value && portController.text == '3010') {
                                portController.text = '443';
                              } else if (!value &&
                                  portController.text == '443') {
                                portController.text = '3010';
                              }
                            });
                          },
                          activeThumbColor: Colors.green,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.notifications_active_outlined,
                              color: Colors.blue,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Central FCM / SMT',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Guardar central y conectar FCM',
                              child: InkWell(
                                onTap: isLoadingFcmConfig ||
                                        isSaving ||
                                        isConnectingDeviceFcm
                                    ? null
                                    : () => connectDeviceFcm(setDialogState),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color:
                                        fcmStateColor.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color:
                                          fcmStateColor.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: isConnectingDeviceFcm
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: fcmStateColor,
                                          ),
                                        )
                                      : Icon(
                                          Icons.link_rounded,
                                          color: fcmStateColor,
                                          size: 18,
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Esta configuracion se guarda en el backend seleccionado y controla el proxy hacia el central para solicitudes SMT y registro FCM.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: fcmStateColor.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    fcmStateIcon,
                                    color: fcmStateColor,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      fcmStateTitle,
                                      style: TextStyle(
                                        color: fcmStateColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              _buildFcmStatusRow(
                                'Permiso',
                                deviceFcmStatus.permissionLabel,
                                deviceFcmStatus.permissionStatus ==
                                        AuthorizationStatus.authorized
                                    ? Colors.greenAccent
                                    : Colors.white70,
                              ),
                              _buildFcmStatusRow(
                                'Token',
                                deviceFcmStatus.shortToken,
                                deviceFcmStatus.hasToken
                                    ? Colors.greenAccent
                                    : Colors.white70,
                              ),
                              _buildFcmStatusRow(
                                'Backend',
                                deviceFcmStatus.backendLabel,
                                deviceFcmStatus.backendRegistered == true
                                    ? Colors.greenAccent
                                    : deviceFcmStatus.backendRegistered == false
                                        ? Colors.orangeAccent
                                        : Colors.white70,
                              ),
                              _buildFcmStatusRow(
                                'Topic',
                                deviceFcmStatus.topicLabel,
                                deviceFcmStatus.topicReady
                                    ? Colors.greenAccent
                                    : deviceFcmStatus.topicSubscribed == false
                                        ? Colors.orangeAccent
                                        : Colors.white70,
                              ),
                              if (deviceFcmMessage != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  deviceFcmMessage!,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                  ),
                                ),
                              ] else if (deviceFcmStatus.lastError != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  deviceFcmStatus.lastError!,
                                  style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 11,
                                  ),
                                ),
                              ] else if (deviceFcmStatus.backendMessage !=
                                      null ||
                                  deviceFcmStatus.topicMessage != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  deviceFcmStatus.backendMessage ??
                                      deviceFcmStatus.topicMessage!,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (isLoadingFcmConfig)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else ...[
                          TextField(
                            controller: centralHostController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'IP o Hostname central',
                              labelStyle: TextStyle(color: Colors.white70),
                              hintText: 'Ej: 100.79.250.73',
                              hintStyle: TextStyle(color: Colors.white38),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.blue),
                              ),
                            ),
                            keyboardType: TextInputType.url,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: centralPortController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Puerto central',
                              labelStyle: TextStyle(color: Colors.white70),
                              hintText: '4000',
                              hintStyle: TextStyle(color: Colors.white38),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.blue),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: centralUseHttps
                                    ? Colors.green.withValues(alpha: 0.5)
                                    : Colors.white24,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  centralUseHttps
                                      ? Icons.lock
                                      : Icons.lock_open,
                                  color: centralUseHttps
                                      ? Colors.green
                                      : Colors.white54,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Central usa HTTPS',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        centralUseHttps
                                            ? 'Conexion segura hacia el central'
                                            : 'Conexion HTTP hacia el central',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.5),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: centralUseHttps,
                                  onChanged: (value) {
                                    setDialogState(() {
                                      centralUseHttps = value;
                                      if (value &&
                                          centralPortController.text ==
                                              '4000') {
                                        centralPortController.text = '443';
                                      } else if (!value &&
                                          centralPortController.text == '443') {
                                        centralPortController.text = '4000';
                                      }
                                    });
                                  },
                                  activeThumbColor: Colors.green,
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (fcmConfigMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            fcmConfigMessage!,
                            style: TextStyle(
                              color: fcmConfigSuccess == false
                                  ? Colors.orangeAccent
                                  : Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = nameController.text.trim();
                        final ip = ipController.text.trim();
                        final port =
                            int.tryParse(portController.text.trim()) ?? 3010;
                        final centralHost = centralHostController.text.trim();
                        final centralPort =
                            int.tryParse(centralPortController.text.trim()) ??
                                4000;

                        if (name.isEmpty || ip.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Nombre e IP son requeridos'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        if (centralHost.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'La IP/Hostname central para FCM es requerida'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        setDialogState(() {
                          isSaving = true;
                        });

                        final serverToSave = isEditing
                            ? existingServer.copyWith(
                                name: name,
                                ip: ip,
                                port: port,
                                useHttps: useHttps,
                              )
                            : ServerProfile(
                                id: DateTime.now()
                                    .millisecondsSinceEpoch
                                    .toString(),
                                name: name,
                                ip: ip,
                                port: port,
                                useHttps: useHttps,
                              );

                        if (isEditing) {
                          await ServerConfig.updateServer(serverToSave);
                        } else {
                          await ServerConfig.addServer(serverToSave);
                        }

                        final fcmResult =
                            await ServerConfig.updateSmtRequestsConfig(
                          serverToSave,
                          centralHost: centralHost,
                          centralPort: centralPort,
                          centralUseHttps: centralUseHttps,
                        );

                        if (!mounted) return;

                        if (fcmResult['success'] == true) {
                          Navigator.pop(context);
                          setState(() {
                            _connectionStatus = null;
                          });
                          widget.onServerChanged?.call();
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                fcmResult['success'] == true
                                    ? 'Servidor y configuracion FCM guardados'
                                    : 'Servidor guardado, pero FCM no se pudo actualizar: ${fcmResult['error'] ?? 'error desconocido'}',
                              ),
                              backgroundColor: fcmResult['success'] == true
                                  ? Colors.green
                                  : Colors.orange,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        } else {
                          setDialogState(() {
                            isSaving = false;
                            fcmConfigSuccess = false;
                            fcmConfigMessage =
                                'No se pudo guardar la configuracion FCM: ${fcmResult['error'] ?? 'error desconocido'}';
                            deviceFcmMessage =
                                'Corrige la configuracion central o usa el icono de conectar para probarla.';
                          });
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(isEditing ? 'Guardar' : 'Agregar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteServer(ServerProfile server) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E2C),
        title: const Text(
          'Eliminar servidor',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '¿Está seguro de eliminar "${server.name}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              await ServerConfig.removeServer(server.id);
              if (mounted) {
                Navigator.pop(context);
                setState(() {
                  _connectionStatus = null;
                });
                widget.onServerChanged?.call();
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

/// Widget compacto para mostrar el servidor activo (solo lectura)
/// Usado en headers o áreas pequeñas
class ServerStatusBadge extends StatelessWidget {
  final bool compact;

  const ServerStatusBadge({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final server = ServerConfig.activeServer;
    final isMobileLocalhost = Platform.isAndroid &&
        server != null &&
        ['localhost', '127.0.0.1', '0.0.0.0']
            .contains(server.ip.trim().toLowerCase());

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isMobileLocalhost
              ? Colors.amber.withOpacity(0.18)
              : Colors.black26,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns,
              size: 12,
              color: isMobileLocalhost ? Colors.amber : Colors.white54,
            ),
            const SizedBox(width: 4),
            Text(
              server?.name ?? 'N/A',
              style: TextStyle(
                color: isMobileLocalhost ? Colors.amber : Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      'Servidor: ${server?.displayString ?? "No configurado"}',
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:material_warehousing_flutter/core/config/server_config.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

/// Dialog para mostrar y compartir la configuración del servidor via QR
/// Se usa en desktop para que los dispositivos móviles puedan escanear
class ServerQrDialog extends StatefulWidget {
  const ServerQrDialog({super.key});

  /// Muestra el dialog de QR
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const ServerQrDialog(),
    );
  }

  @override
  State<ServerQrDialog> createState() => _ServerQrDialogState();
}

class _ServerQrDialogState extends State<ServerQrDialog> {
  String? _localIp;
  bool _isLoadingIp = true;

  @override
  void initState() {
    super.initState();
    _loadLocalIp();
  }

  Future<void> _loadLocalIp() async {
    final ip = await ServerConfig.getLocalIpAddress();
    setState(() {
      _localIp = ip;
      _isLoadingIp = false;
    });
  }

  String _generateQrData() {
    final server = ServerConfig.activeServer;
    if (server == null) return '';
    
    // Usar la IP local de la máquina para que el móvil pueda conectar
    final ip = _localIp ?? server.ip;
    
    return json.encode({
      'name': server.name,
      'ip': ip,
      'port': server.port,
    });
  }

  @override
  Widget build(BuildContext context) {
    final server = ServerConfig.activeServer;
    final qrData = _generateQrData();

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1E2C),
      title: Row(
        children: [
          const Icon(Icons.qr_code_2, color: AppColors.headerTab),
          const SizedBox(width: 12),
          const Text(
            'Conectar Dispositivo Móvil',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // QR Code
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _isLoadingIp
                  ? const SizedBox(
                      width: 200,
                      height: 200,
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                      errorStateBuilder: (context, error) {
                        return const Center(
                          child: Text(
                            'Error generando QR',
                            style: TextStyle(color: Colors.red),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),
            
            // Instrucciones
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF252A3C),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Instrucciones:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildInstruction('1', 'Abra la app en su dispositivo Android'),
                  _buildInstruction('2', 'En el login, toque "Configurar servidor"'),
                  _buildInstruction('3', 'Seleccione "Escanear QR"'),
                  _buildInstruction('4', 'Apunte la cámara a este código'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Info del servidor
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.dns, color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server?.name ?? 'Servidor',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _isLoadingIp 
                              ? 'Obteniendo IP...'
                              : '${_localIp ?? server?.ip}:${server?.port}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Advertencia si no hay IP local
            if (!_isLoadingIp && _localIp == null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No se pudo detectar la IP local. Asegúrese de estar conectado a la red.',
                        style: TextStyle(
                          color: Colors.orange.shade200,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        if (!_isLoadingIp && _localIp != null)
          ElevatedButton.icon(
            onPressed: _refreshIp,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Actualizar IP'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.headerTab,
            ),
          ),
      ],
    );
  }

  Widget _buildInstruction(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.headerTab.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: AppColors.headerTab,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshIp() async {
    setState(() {
      _isLoadingIp = true;
    });
    await _loadLocalIp();
  }
}

/// Widget de botón para abrir el QR dialog
/// Se puede agregar en la pantalla de settings o en el header
class ServerQrButton extends StatelessWidget {
  final bool compact;
  
  const ServerQrButton({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        icon: const Icon(Icons.qr_code_2, color: Colors.white70),
        onPressed: () => ServerQrDialog.show(context),
        tooltip: 'Conectar dispositivo móvil',
      );
    }

    return ElevatedButton.icon(
      onPressed: () => ServerQrDialog.show(context),
      icon: const Icon(Icons.qr_code_2),
      label: const Text('Conectar Móvil'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.headerTab.withOpacity(0.8),
        foregroundColor: Colors.white,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';

class ScrapMotivosScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const ScrapMotivosScreen({super.key, required this.languageProvider});

  @override
  State<ScrapMotivosScreen> createState() => ScrapMotivosScreenState();
}

class ScrapMotivosScreenState extends State<ScrapMotivosScreen>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _motivos = [];
  bool _isLoading = false;
  bool _showInactive = false;

  String tr(String key) => widget.languageProvider.tr(key);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMotivos();
  }

  Future<void> _loadMotivos() async {
    setState(() => _isLoading = true);
    final result =
        await ApiService.getScrapMotivos(includeInactive: _showInactive);
    if (mounted) {
      setState(() {
        _motivos =
            (result['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _isLoading = false;
      });
    }
  }

  Future<void> _addMotivo() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Text(tr('scrap_add_motivo'),
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: SizedBox(
          width: 350,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: tr('scrap_motivo'),
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel'),
                style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child:
                Text(tr('save'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final resp = await ApiService.createScrapMotivo(
        motivo: result,
        usuario: AuthService.currentUser?.nombreCompleto,
      );
      if (resp['success'] == true) {
        _loadMotivos();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(resp['message'] ?? 'Error'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _editMotivo(Map<String, dynamic> motivo) async {
    final controller = TextEditingController(text: motivo['motivo'] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Text(tr('scrap_edit_motivo'),
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: SizedBox(
          width: 350,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: tr('scrap_motivo'),
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel'),
                style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child:
                Text(tr('save'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != motivo['motivo']) {
      final resp = await ApiService.updateScrapMotivo(
        id: motivo['id'],
        motivo: result,
        usuario: AuthService.currentUser?.nombreCompleto,
      );
      if (resp['success'] == true) {
        _loadMotivos();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(resp['message'] ?? 'Error'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _toggleActivo(Map<String, dynamic> motivo) async {
    final nuevoEstado = (motivo['activo'] ?? 1) == 1 ? false : true;
    await ApiService.updateScrapMotivo(
      id: motivo['id'],
      activo: nuevoEstado,
      usuario: AuthService.currentUser?.nombreCompleto,
    );
    _loadMotivos();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        // Toolbar
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.panelBackground,
            border:
                Border(bottom: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: Row(
            children: [
              Text(
                tr('scrap_motivos_title'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 16),
              SizedBox(
                height: 32,
                child: ElevatedButton.icon(
                  onPressed: _addMotivo,
                  icon: const Icon(Icons.add, size: 14),
                  label: Text(tr('scrap_add_motivo'),
                      style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 32,
                child: OutlinedButton.icon(
                  onPressed: _loadMotivos,
                  icon: const Icon(Icons.refresh,
                      size: 14, color: Colors.white70),
                  label: Text(tr('scrap_refresh'),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _showInactive,
                  onChanged: (v) {
                    setState(() => _showInactive = v ?? false);
                    _loadMotivos();
                  },
                  side: const BorderSide(color: AppColors.border),
                  activeColor: Colors.blue,
                ),
              ),
              const SizedBox(width: 6),
              Text(tr('scrap_show_inactive'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const Spacer(),
            ],
          ),
        ),
        // Header
        Container(
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.gridHeader,
            border:
                Border(bottom: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: Row(
            children: [
              _headerCell(tr('scrap_motivo'), flex: 3),
              _headerCell(tr('scrap_activo'), flex: 1),
              _headerCell(tr('scrap_created_by'), flex: 2),
              _headerCell(tr('scrap_created_at'), flex: 2),
              _headerCell(tr('scrap_updated_by'), flex: 2),
              _headerCell(tr('scrap_updated_at'), flex: 2),
              _headerCell(tr('scrap_actions'), flex: 1),
            ],
          ),
        ),
        // Body
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _motivos.isEmpty
                  ? Center(
                      child: Text(tr('scrap_no_motivos'),
                          style: const TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      itemCount: _motivos.length,
                      itemBuilder: (context, index) {
                        final m = _motivos[index];
                        final isActive = (m['activo'] ?? 1) == 1;
                        return Container(
                          height: 30,
                          decoration: BoxDecoration(
                            color: index.isEven
                                ? AppColors.gridRowEven
                                : AppColors.gridRowOdd,
                            border: Border(
                                bottom: BorderSide(
                                    color: AppColors.border.withOpacity(0.3))),
                          ),
                          child: Row(
                            children: [
                              _dataCell(m['motivo'] ?? '', flex: 3),
                              Expanded(
                                flex: 1,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: Icon(
                                    isActive
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    color: isActive
                                        ? Colors.green
                                        : Colors.red.withOpacity(0.5),
                                    size: 16,
                                  ),
                                ),
                              ),
                              _dataCell(m['creado_por'] ?? '', flex: 2),
                              _dataCell(m['fecha_creacion'] ?? '', flex: 2),
                              _dataCell(m['actualizado_por'] ?? '', flex: 2),
                              _dataCell(m['fecha_actualizacion'] ?? '',
                                  flex: 2),
                              Expanded(
                                flex: 1,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    InkWell(
                                      onTap: () => _editMotivo(m),
                                      child: const Padding(
                                        padding: EdgeInsets.all(2),
                                        child: Icon(Icons.edit,
                                            size: 14, color: Colors.blue),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () => _toggleActivo(m),
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Icon(
                                          isActive
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                          size: 14,
                                          color: isActive
                                              ? Colors.orange
                                              : Colors.green,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
        // Footer
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.panelBackground,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: Row(
            children: [
              Text(
                '${tr('total')}: ${_motivos.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          text,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _dataCell(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

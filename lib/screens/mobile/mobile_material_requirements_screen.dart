import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_requirement_draft.dart';
import 'package:material_warehousing_flutter/screens/mobile/mobile_requirement_form_screen.dart';

class MobileMaterialRequirementsScreen extends StatefulWidget {
  final LanguageProvider languageProvider;

  const MobileMaterialRequirementsScreen({
    super.key,
    required this.languageProvider,
  });

  @override
  State<MobileMaterialRequirementsScreen> createState() =>
      _MobileMaterialRequirementsScreenState();
}

class _MobileMaterialRequirementsScreenState
    extends State<MobileMaterialRequirementsScreen> {
  List<Map<String, dynamic>> _requirements = [];
  List<String> _areas = [];
  String? _selectedArea;
  bool _pendingOnly = true;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final areas = await ApiService.getRequirementAreas();
    if (mounted) setState(() => _areas = areas);
    await _loadRequirements();
  }

  Future<void> _loadRequirements() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await ApiService.getRequirements(
        area: _selectedArea,
        pendingOnly: _pendingOnly,
        throwOnError: true,
      );
      if (!mounted) return;
      setState(() {
        _requirements = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createRequirement() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => MobileRequirementFormScreen(
          languageProvider: widget.languageProvider,
        ),
      ),
    );
    if (result == null || !mounted) return;

    await _loadRequirements();
    final id = int.tryParse(result['id']?.toString() ?? '');
    if (id != null && mounted) await _openRequirement(id);
  }

  Future<void> _openRequirement(int id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MobileRequirementDetailScreen(
          requirementId: id,
          languageProvider: widget.languageProvider,
        ),
      ),
    );
    if (mounted) await _loadRequirements();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      color: const Color(0xFF252A3C),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Pendientes'),
                      icon: Icon(Icons.pending_actions),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Todos'),
                      icon: Icon(Icons.list_alt),
                    ),
                  ],
                  selected: {_pendingOnly},
                  onSelectionChanged: (selection) {
                    setState(() => _pendingOnly = selection.first);
                    _loadRequirements();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: _loading ? null : _loadRequirements,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _selectedArea,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Área',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todas las áreas'),
                    ),
                    ..._areas.map((area) => DropdownMenuItem<String?>(
                          value: area,
                          child: Text(area),
                        )),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedArea = value);
                    _loadRequirements();
                  },
                ),
              ),
              if (AuthService.canWriteRequirements) ...[
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _createRequirement,
                  icon: const Icon(Icons.add),
                  label: const Text('NUEVO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 15,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _MessageState(
        icon: Icons.cloud_off,
        message: 'No fue posible cargar los requerimientos.',
        actionLabel: 'Reintentar',
        onAction: _loadRequirements,
      );
    }
    if (_requirements.isEmpty) {
      return _MessageState(
        icon: Icons.assignment_turned_in_outlined,
        message: _pendingOnly
            ? 'No hay requerimientos pendientes.'
            : 'No hay requerimientos para mostrar.',
        actionLabel: 'Actualizar',
        onAction: _loadRequirements,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequirements,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _requirements.length,
        itemBuilder: (context, index) =>
            _buildRequirementCard(_requirements[index]),
      ),
    );
  }

  Widget _buildRequirementCard(Map<String, dynamic> requirement) {
    final id = int.tryParse(requirement['id']?.toString() ?? '');
    final status = requirement['status']?.toString() ?? 'Pendiente';
    final priority = requirement['prioridad']?.toString() ?? 'Normal';
    final statusColor = _statusColor(status);

    return Card(
      color: const Color(0xFF252A3C),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: id == null ? null : () => _openRequirement(id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      requirement['codigo_requerimiento']?.toString() ??
                          'REQ-${requirement['id']}',
                      style: const TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _Badge(label: status, color: statusColor),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.factory_outlined,
                      color: Colors.white54, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    requirement['area_destino']?.toString() ?? '-',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  _Badge(label: priority, color: _priorityColor(priority)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today,
                      color: Colors.white54, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _formatDate(requirement['fecha_requerida']),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  const Icon(Icons.inventory_2_outlined,
                      color: Colors.white54, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${requirement['total_items'] ?? 0} materiales',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MobileRequirementDetailScreen extends StatefulWidget {
  final int requirementId;
  final LanguageProvider languageProvider;

  const MobileRequirementDetailScreen({
    super.key,
    required this.requirementId,
    required this.languageProvider,
  });

  @override
  State<MobileRequirementDetailScreen> createState() =>
      _MobileRequirementDetailScreenState();
}

class _MobileRequirementDetailScreenState
    extends State<MobileRequirementDetailScreen> {
  Map<String, dynamic>? _requirement;
  bool _loading = true;
  bool _mutating = false;

  String get _status =>
      _requirement?['status']?.toString().trim() ?? 'Pendiente';

  bool get _canAddMaterials => canAddMaterialsToRequirement(
        _status,
        canWrite: AuthService.canWriteRequirements,
      );

  bool get _canCancel => canCancelRequirement(
        _status,
        canWrite: AuthService.canWriteRequirements,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final result = await ApiService.getRequirementById(widget.requirementId);
    if (!mounted) return;
    setState(() {
      _requirement = result;
      _loading = false;
    });
  }

  Future<void> _addMaterials() async {
    if (!_canAddMaterials || _mutating) return;
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => MobileRequirementFormScreen(
          languageProvider: widget.languageProvider,
          appendToRequirementId: widget.requirementId,
          requirementCode: _requirement?['codigo_requerimiento']?.toString(),
        ),
      ),
    );
    if (result?['success'] != true || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result?['message']?.toString() ??
            'Materiales agregados al requerimiento.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _cancelRequirement() async {
    if (!_canCancel || _mutating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar requerimiento'),
        content: Text(
          '¿Deseas cancelar ${_requirement?['codigo_requerimiento'] ?? 'este requerimiento'}? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Sí, cancelar'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _mutating = true);
    final user = AuthService.currentUser;
    final result = await ApiService.cancelRequirementDetailed(
      widget.requirementId,
      user?.nombreCompleto ?? user?.username,
    );
    if (!mounted) return;
    setState(() => _mutating = false);

    if (result['success'] == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Requerimiento cancelado.'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['error']?.toString() ??
              'No fue posible cancelar el requerimiento.',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1E2C),
      appBar: AppBar(
        title: Text(
          _requirement?['codigo_requerimiento']?.toString() ??
              'Detalle del requerimiento',
        ),
        backgroundColor: const Color(0xFF252A3C),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requirement == null
              ? _MessageState(
                  icon: Icons.error_outline,
                  message: 'No se encontró el requerimiento.',
                  actionLabel: 'Reintentar',
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _buildHeader(),
                      if (AuthService.canWriteRequirements) ...[
                        const SizedBox(height: 14),
                        _buildActions(),
                      ],
                      const SizedBox(height: 14),
                      _buildItems(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildActions() {
    return Card(
      color: const Color(0xFF252A3C),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_canAddMaterials)
              ElevatedButton.icon(
                onPressed: _mutating ? null : _addMaterials,
                icon: const Icon(Icons.playlist_add),
                label: const Text('AGREGAR MATERIALES'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              )
            else if (_status != 'Cancelado' && _status != 'Entregado')
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Ya no se pueden agregar materiales porque el requerimiento no está Pendiente (estado: $_status).',
                  style: const TextStyle(color: Colors.amber),
                ),
              ),
            if (_canCancel)
              OutlinedButton.icon(
                onPressed: _mutating ? null : _cancelRequirement,
                icon: _mutating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cancel_outlined),
                label: Text(_mutating ? 'CANCELANDO...' : 'CANCELAR'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                ),
              ),
            if (!_canAddMaterials && !_canCancel)
              Text(
                _status == 'Cancelado'
                    ? 'Este requerimiento fue cancelado.'
                    : 'Este requerimiento ya fue entregado.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final data = _requirement!;
    final status = data['status']?.toString() ?? 'Pendiente';
    final priority = data['prioridad']?.toString() ?? 'Normal';
    return Card(
      color: const Color(0xFF252A3C),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data['codigo_requerimiento']?.toString() ?? '',
                    style: const TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _Badge(label: status, color: _statusColor(status)),
              ],
            ),
            const Divider(height: 24),
            _DetailRow(label: 'Área destino', value: data['area_destino']),
            _DetailRow(label: 'Modelo', value: data['modelo']),
            _DetailRow(
                label: 'Fecha requerida',
                value: _formatDate(data['fecha_requerida'])),
            _DetailRow(label: 'Turno', value: data['turno']),
            _DetailRow(label: 'Prioridad', value: priority),
            _DetailRow(label: 'Creado por', value: data['creado_por']),
            if ((data['notas']?.toString() ?? '').isNotEmpty)
              _DetailRow(label: 'Notas', value: data['notas']),
          ],
        ),
      ),
    );
  }

  Widget _buildItems() {
    final rawItems = _requirement!['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    return Card(
      color: const Color(0xFF252A3C),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Materiales (${items.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('Sin materiales',
                      style: TextStyle(color: Colors.white54)),
                ),
              )
            else
              ...items.map(_buildRequirementItem),
          ],
        ),
      ),
    );
  }

  Widget _buildRequirementItem(Map<String, dynamic> item) {
    final available = _requirementItemInt(item['cantidad_disponible']);
    final pending = _requirementItemInt(item['cantidad_pendiente_entrada']);
    final invoices = (item['invoices_pendientes'] ?? '').toString().trim();
    final pendingOnly = available <= 0 && pending > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E2C),
        borderRadius: BorderRadius.circular(10),
        border: pendingOnly ? Border.all(color: Colors.orangeAccent) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item['numero_parte']?.toString() ?? '-',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item['descripcion']?.toString() ??
                item['especificacion_material']?.toString() ??
                'Sin descripción',
            style: const TextStyle(color: Colors.white60),
          ),
          if (pendingOnly) ...[
            const SizedBox(height: 8),
            Text(
              invoices.isEmpty || invoices == 'null'
                  ? '⏳ Sin existencia; $pending pendiente por invoice.'
                  : '⏳ Sin existencia; $pending pendiente en $invoices.',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                'Requerida: ${item['cantidad_requerida'] ?? 0}',
                style: const TextStyle(color: Colors.tealAccent),
              ),
              Text(
                'Entregada: ${item['cantidad_entregada'] ?? 0}',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                item['status']?.toString() ?? 'Pendiente',
                style: const TextStyle(color: Colors.amber),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _requirementItemInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final dynamic value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = value?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.white54)),
          ),
          Expanded(
            child: Text(
              text.isEmpty ? '-' : text,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _MessageState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white24, size: 64),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(dynamic value) {
  if (value == null) return '-';
  try {
    return DateFormat('dd/MM/yyyy').format(DateTime.parse(value.toString()));
  } catch (_) {
    return value.toString();
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'En Preparación':
      return Colors.blue;
    case 'Listo':
      return Colors.green;
    case 'Entregado':
      return Colors.teal;
    case 'Cancelado':
      return Colors.red;
    default:
      return Colors.orange;
  }
}

Color _priorityColor(String priority) {
  switch (priority) {
    case 'Crítico':
      return Colors.red;
    case 'Urgente':
      return Colors.orange;
    default:
      return Colors.blueGrey;
  }
}

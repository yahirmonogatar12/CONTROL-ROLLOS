import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/widgets/grid_footer.dart';

class UserManagementScreen extends StatefulWidget {
  final LanguageProvider languageProvider;
  
  const UserManagementScreen({super.key, required this.languageProvider});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  List<String> _departments = [];
  List<String> _cargos = [];
  List<Map<String, dynamic>> _availablePermissions = [];
  bool _isLoading = false;
  int _selectedIndex = -1;
  Map<String, dynamic>? _selectedUser;
  
  // Permisos del usuario seleccionado
  Map<String, bool> _userPermissions = {};
  
  // Form controllers
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _nombreController = TextEditingController();
  String? _selectedDepartment;
  String? _selectedCargo;
  bool _isEditing = false;
  int? _editingUserId;
  
  // Search
  final _searchController = TextEditingController();
  
  String tr(String key) => widget.languageProvider.tr(key);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _nombreController.dispose();
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    final results = await Future.wait([
      ApiService.getUsers(),
      ApiService.getDepartments(),
      ApiService.getCargos(),
      ApiService.getAvailablePermissions(),
    ]);
    
    if (mounted) {
      setState(() {
        _users = results[0] as List<Map<String, dynamic>>;
        _filteredUsers = List.from(_users);
        _departments = results[1] as List<String>;
        _cargos = results[2] as List<String>;
        _availablePermissions = results[3] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadUserPermissions(int userId) async {
    final permissions = await ApiService.getUserPermissions(userId);
    
    // Reset all permissions
    _userPermissions = {};
    for (var perm in _availablePermissions) {
      _userPermissions[perm['key']] = false;
    }
    
    // Set enabled permissions
    for (var perm in permissions) {
      if (perm['enabled'] == 1) {
        _userPermissions[perm['permission_key']] = true;
      }
    }
    
    setState(() {});
  }
  
  void _selectUser(int index) {
    setState(() {
      _selectedIndex = index;
      _selectedUser = _filteredUsers[index];
    });
    _loadUserPermissions(_selectedUser!['id']);
  }
  
  void _filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = List.from(_users);
      } else {
        _filteredUsers = _users.where((user) {
          final username = user['username']?.toString().toLowerCase() ?? '';
          final nombre = user['nombre_completo']?.toString().toLowerCase() ?? '';
          final depto = user['departamento']?.toString().toLowerCase() ?? '';
          final searchLower = query.toLowerCase();
          return username.contains(searchLower) || 
                 nombre.contains(searchLower) || 
                 depto.contains(searchLower);
        }).toList();
      }
      _selectedIndex = -1;
      _selectedUser = null;
    });
  }
  
  void _clearForm() {
    _usernameController.clear();
    _passwordController.clear();
    _emailController.clear();
    _nombreController.clear();
    _selectedDepartment = null;
    _selectedCargo = null;
    _isEditing = false;
    _editingUserId = null;
    setState(() {});
  }
  
  void _editUser(Map<String, dynamic> user) {
    setState(() {
      _isEditing = true;
      _editingUserId = user['id'];
      _usernameController.text = user['username'] ?? '';
      _passwordController.clear();
      _emailController.text = user['email'] ?? '';
      _nombreController.text = user['nombre_completo'] ?? '';
      _selectedDepartment = user['departamento'];
      _selectedCargo = user['cargo'];
    });
  }
  
  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedDepartment == null || _selectedCargo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('select_department_and_position')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    Map<String, dynamic> result;
    
    if (_isEditing && _editingUserId != null) {
      result = await ApiService.updateUser(
        id: _editingUserId!,
        email: _emailController.text.isNotEmpty ? _emailController.text : null,
        nombreCompleto: _nombreController.text,
        departamento: _selectedDepartment!,
        cargo: _selectedCargo!,
      );
    } else {
      if (_passwordController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('password_required')),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      result = await ApiService.createUser(
        username: _usernameController.text,
        password: _passwordController.text,
        email: _emailController.text.isNotEmpty ? _emailController.text : null,
        nombreCompleto: _nombreController.text,
        departamento: _selectedDepartment!,
        cargo: _selectedCargo!,
      );
    }
    
    if (result['success'] == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? tr('user_updated') : tr('user_created')),
          backgroundColor: Colors.green,
        ),
      );
      _clearForm();
      _loadData();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _toggleUserActive(Map<String, dynamic> user) async {
    final result = await ApiService.toggleUserActive(user['id']);
    
    if (result['success'] == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['activo'] == 1 ? tr('user_activated') : tr('user_deactivated')),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    }
  }
  
  Future<void> _changePassword(Map<String, dynamic> user) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        title: Row(
          children: [
            const Icon(Icons.lock_reset, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Text(tr('change_password'), style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                user['nombre_completo'] ?? user['username'],
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: tr('new_password'),
                  labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                  filled: true,
                  fillColor: AppColors.gridBackground,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: tr('confirm_password'),
                  labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                  filled: true,
                  fillColor: AppColors.gridBackground,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (passwordController.text.isEmpty || passwordController.text.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mínimo 4 caracteres'), backgroundColor: Colors.orange),
                );
                return;
              }
              if (passwordController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('passwords_dont_match')), backgroundColor: Colors.orange),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(tr('save')),
          ),
        ],
      ),
    );
    
    if (result == true) {
      final changeResult = await ApiService.changeUserPassword(
        id: user['id'],
        newPassword: passwordController.text,
      );
      
      if (changeResult['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('password_changed')), backgroundColor: Colors.green),
        );
      }
    }
    
    passwordController.dispose();
    confirmController.dispose();
  }
  
  Future<void> _savePermissions() async {
    if (_selectedUser == null) return;
    
    final permissions = _userPermissions.entries
        .map((e) => {'permission_key': e.key, 'enabled': e.value})
        .toList();
    
    final result = await ApiService.updateUserPermissions(
      userId: _selectedUser!['id'],
      permissions: permissions,
    );
    
    if (result['success'] == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('permissions_saved')),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.panelBackground,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.panelBackground,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.admin_panel_settings, color: Colors.orange, size: 24),
                const SizedBox(width: 12),
                Text(
                  tr('user_management'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Search
                SizedBox(
                  width: 250,
                  height: 32,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: tr('search'),
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                      prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white38),
                      filled: true,
                      fillColor: AppColors.gridBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onChanged: _filterUsers,
                  ),
                ),
              ],
            ),
          ),
          
          // Tabs
          Container(
            color: AppColors.gridHeader,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.orange,
              labelColor: Colors.orange,
              unselectedLabelColor: Colors.white60,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people, size: 16),
                      const SizedBox(width: 8),
                      Text(tr('users')),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.security, size: 16),
                      const SizedBox(width: 8),
                      Text(tr('permissions')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUsersTab(),
                _buildPermissionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUsersTab() {
    return Row(
      children: [
        // Left: User List
        Expanded(
          flex: 3,
          child: _buildUserList(),
        ),
        
        // Divider
        Container(width: 1, color: AppColors.border),
        
        // Right: User Form
        Expanded(
          flex: 2,
          child: _buildUserForm(),
        ),
      ],
    );
  }
  
  Widget _buildPermissionsTab() {
    if (_selectedUser == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              tr('select_user_for_permissions'),
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              tr('click_user_in_users_tab'),
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
            ),
          ],
        ),
      );
    }
    
    // Group permissions by category
    Map<String, List<Map<String, dynamic>>> groupedPermissions = {};
    for (var perm in _availablePermissions) {
      final category = perm['category'] ?? 'Otros';
      groupedPermissions.putIfAbsent(category, () => []);
      groupedPermissions[category]!.add(perm);
    }
    
    return Column(
      children: [
        // User info header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.gridHeader,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.orange.withOpacity(0.2),
                child: Text(
                  (_selectedUser!['nombre_completo'] ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedUser!['nombre_completo'] ?? _selectedUser!['username'],
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_selectedUser!['departamento']} - ${_selectedUser!['cargo']}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _savePermissions,
                icon: const Icon(Icons.save, size: 16),
                label: Text(tr('save_permissions')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        
        // Permissions grid
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: groupedPermissions.entries.map((entry) {
                return _buildPermissionCategory(entry.key, entry.value);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildPermissionCategory(String category, List<Map<String, dynamic>> permissions) {
    // Get category icon and color
    IconData categoryIcon;
    Color categoryColor;
    
    switch (category) {
      case 'Almacén':
        categoryIcon = Icons.warehouse;
        categoryColor = Colors.blue;
        break;
      case 'Calidad':
        categoryIcon = Icons.verified;
        categoryColor = Colors.green;
        break;
      case 'Sistema':
        categoryIcon = Icons.settings;
        categoryColor = Colors.orange;
        break;
      case 'Reportes':
        categoryIcon = Icons.bar_chart;
        categoryColor = Colors.purple;
        break;
      case 'Inventario PCB':
        categoryIcon = Icons.memory;
        categoryColor = Colors.teal;
        break;
      case 'Auditoría':
        categoryIcon = Icons.fact_check;
        categoryColor = Colors.indigo;
        break;
      case 'Catálogo':
        categoryIcon = Icons.library_books;
        categoryColor = Colors.cyan;
        break;
      case 'Producción':
        categoryIcon = Icons.precision_manufacturing;
        categoryColor = Colors.deepOrange;
        break;
      case 'SMT':
        categoryIcon = Icons.notifications_active;
        categoryColor = Colors.amber;
        break;
      default:
        categoryIcon = Icons.folder;
        categoryColor = Colors.grey;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.gridBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: categoryColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(categoryIcon, size: 18, color: categoryColor),
                const SizedBox(width: 8),
                Text(
                  category,
                  style: TextStyle(
                    color: categoryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Toggle all in category
                TextButton(
                  onPressed: () {
                    final allEnabled = permissions.every((p) => _userPermissions[p['key']] == true);
                    setState(() {
                      for (var perm in permissions) {
                        _userPermissions[perm['key']] = !allEnabled;
                      }
                    });
                  },
                  child: Text(
                    permissions.every((p) => _userPermissions[p['key']] == true) 
                        ? tr('disable_all') 
                        : tr('enable_all'),
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          
          // Permissions list
          ...permissions.map((perm) => _buildPermissionTile(perm)),
        ],
      ),
    );
  }
  
  Widget _buildPermissionTile(Map<String, dynamic> permission) {
    final key = permission['key'];
    final isEnabled = _userPermissions[key] ?? false;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  permission['name'] ?? key,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                if (permission['description'] != null)
                  Text(
                    permission['description'],
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
              ],
            ),
          ),
          Switch(
            value: isEnabled,
            onChanged: (val) {
              setState(() {
                _userPermissions[key] = val;
              });
            },
            activeColor: Colors.orange,
            activeTrackColor: Colors.orange.withOpacity(0.3),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUserList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.orange));
    }
    
    return Column(
      children: [
        // Header
        Container(
          height: 36,
          color: AppColors.gridHeader,
          child: Row(
            children: [
              _buildHeaderCell('ID', 50),
              _buildHeaderCell(tr('username'), 100),
              _buildHeaderCell(tr('full_name'), 150),
              _buildHeaderCell(tr('department'), 120),
              _buildHeaderCell(tr('position'), 100),
              _buildHeaderCell(tr('status'), 70),
              _buildHeaderCell(tr('actions'), 120),
            ],
          ),
        ),
        
        // Data
        Expanded(
          child: _filteredUsers.isEmpty
              ? Center(
                  child: Text(
                    tr('no_users'),
                    style: TextStyle(color: Colors.white.withOpacity(0.3)),
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = _filteredUsers[index];
                    final isSelected = index == _selectedIndex;
                    final isActive = user['activo'] == 1;
                    
                    return GestureDetector(
                      onTap: () => _selectUser(index),
                      onDoubleTap: () => _editUser(user),
                      child: Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.orange.withOpacity(0.2)
                              : index.isEven
                                  ? AppColors.gridBackground
                                  : AppColors.gridRowAlt,
                          border: Border(
                            left: isSelected
                                ? const BorderSide(color: Colors.orange, width: 3)
                                : BorderSide.none,
                          ),
                        ),
                        child: Row(
                          children: [
                            _buildDataCell(user['id'].toString(), 50),
                            _buildDataCell(user['username'] ?? '', 100),
                            _buildDataCell(user['nombre_completo'] ?? '', 150),
                            _buildDataCell(user['departamento'] ?? '', 120),
                            _buildDataCell(user['cargo'] ?? '', 100),
                            SizedBox(
                              width: 70,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isActive ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isActive ? tr('active') : tr('inactive'),
                                    style: TextStyle(
                                      color: isActive ? Colors.green : Colors.red,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 120,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildActionIcon(
                                    Icons.edit,
                                    Colors.cyan,
                                    () => _editUser(user),
                                    tr('edit'),
                                  ),
                                  _buildActionIcon(
                                    Icons.lock_reset,
                                    Colors.orange,
                                    () => _changePassword(user),
                                    tr('change_password'),
                                  ),
                                  _buildActionIcon(
                                    isActive ? Icons.person_off : Icons.person,
                                    isActive ? Colors.red : Colors.green,
                                    () => _toggleUserActive(user),
                                    isActive ? tr('deactivate') : tr('activate'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        
        // Footer
        GridFooter(text: '${tr('total_rows')}: ${_filteredUsers.length}'),
      ],
    );
  }
  
  Widget _buildHeaderCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
  
  Widget _buildDataCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 10),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
  
  Widget _buildActionIcon(IconData icon, Color color, VoidCallback onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
  
  Widget _buildUserForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              children: [
                Icon(
                  _isEditing ? Icons.edit : Icons.person_add,
                  color: Colors.orange,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _isEditing ? tr('edit_user') : tr('create_user'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isEditing)
                  TextButton.icon(
                    onPressed: _clearForm,
                    icon: const Icon(Icons.add, size: 14),
                    label: Text(tr('new'), style: const TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Username
            _buildFormField(
              controller: _usernameController,
              label: tr('username'),
              required: true,
              enabled: !_isEditing,
            ),
            const SizedBox(height: 12),
            
            // Password (solo para nuevo usuario)
            if (!_isEditing) ...[
              _buildFormField(
                controller: _passwordController,
                label: tr('password'),
                required: true,
                obscure: true,
              ),
              const SizedBox(height: 12),
            ],
            
            // Email
            _buildFormField(
              controller: _emailController,
              label: tr('email'),
            ),
            const SizedBox(height: 12),
            
            // Nombre completo
            _buildFormField(
              controller: _nombreController,
              label: tr('full_name'),
              required: true,
            ),
            const SizedBox(height: 12),
            
            // Departamento dropdown
            _buildDropdown(
              label: tr('department'),
              value: _selectedDepartment,
              items: _departments,
              onChanged: (val) => setState(() => _selectedDepartment = val),
            ),
            const SizedBox(height: 12),
            
            // Cargo dropdown
            _buildDropdown(
              label: tr('position'),
              value: _selectedCargo,
              items: _cargos,
              onChanged: (val) => setState(() => _selectedCargo = val),
            ),
            
            const Spacer(),
            
            // Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveUser,
                    icon: Icon(_isEditing ? Icons.save : Icons.add, size: 16),
                    label: Text(_isEditing ? tr('save') : tr('create')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clearForm,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Colors.grey),
                    ),
                    child: Text(tr('cancel'), style: const TextStyle(color: Colors.grey)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    bool required = false,
    bool obscure = false,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      style: TextStyle(
        color: enabled ? Colors.white : Colors.white38,
        fontSize: 12,
      ),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
        filled: true,
        fillColor: enabled ? AppColors.gridBackground : AppColors.gridBackground.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.orange),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      validator: required
          ? (val) => val == null || val.isEmpty ? tr('required_field') : null
          : null,
    );
  }
  
  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    // Asegurar que el valor actual esté en la lista de items
    final validValue = (value != null && items.contains(value)) ? value : null;
    
    return DropdownButtonFormField<String>(
      value: validValue,
      items: items.map((item) => DropdownMenuItem(
        value: item,
        child: Text(item, style: const TextStyle(fontSize: 12)),
      )).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: '$label *',
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
        filled: true,
        fillColor: AppColors.gridBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      dropdownColor: AppColors.panelBackground,
      style: const TextStyle(color: Colors.white, fontSize: 12),
      icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
    );
  }
}

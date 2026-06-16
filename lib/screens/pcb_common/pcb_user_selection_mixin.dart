import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/services/api_service.dart';
import 'package:material_warehousing_flutter/core/services/auth_service.dart';

mixin PcbUserSelectionMixin<T extends StatefulWidget> on State<T> {
  List<Map<String, dynamic>> pcbUsers = [];
  int? selectedPcbUserId;
  String? selectedPcbUserName;

  void setDefaultPcbUser() {
    final currentUser = AuthService.currentUser;
    if (currentUser == null) return;
    selectedPcbUserId = currentUser.id;
    selectedPcbUserName = currentUser.nombreCompleto.isNotEmpty
        ? currentUser.nombreCompleto
        : currentUser.username;
  }

  int? parsePcbUserId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String pcbUserName(Map<String, dynamic> user) {
    final fullName = user['nombre_completo']?.toString().trim() ?? '';
    if (fullName.isNotEmpty) return fullName;
    return user['username']?.toString().trim() ?? '';
  }

  Future<void> loadPcbUsers() async {
    final result = await ApiService.getUsers();
    final users = result.where((user) {
      final active = user['activo']?.toString().toLowerCase();
      return active != '0' && active != 'false';
    }).toList();
    if (!mounted) return;
    setState(() {
      pcbUsers = users;
      if (selectedPcbUserId != null &&
          !pcbUsers
              .any((user) => parsePcbUserId(user['id']) == selectedPcbUserId)) {
        setDefaultPcbUser();
      }
    });
  }

  List<List<String>> get pcbUserRows {
    return pcbUsers.map((user) {
      return [
        user['id']?.toString() ?? '',
        pcbUserName(user),
      ];
    }).toList();
  }

  String get selectedPcbUserDisplay {
    if (selectedPcbUserId == null || (selectedPcbUserName ?? '').isEmpty) {
      return '';
    }
    return '$selectedPcbUserId - $selectedPcbUserName';
  }

  String? get selectedPcbScannedBy {
    final selected = selectedPcbUserName?.trim() ?? '';
    if (selected.isNotEmpty) return selected;
    final currentUser = AuthService.currentUser;
    if (currentUser == null) return null;
    return currentUser.nombreCompleto.isNotEmpty
        ? currentUser.nombreCompleto
        : currentUser.username;
  }

  bool selectPcbUserByIndex(int index) {
    if (index < 0 || index >= pcbUsers.length) return false;
    final user = pcbUsers[index];
    setState(() {
      selectedPcbUserId = parsePcbUserId(user['id']);
      selectedPcbUserName = pcbUserName(user);
    });
    return true;
  }
}

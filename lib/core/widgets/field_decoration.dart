import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

InputDecoration fieldDecoration({String? hintText}) {
  return InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    filled: true,
    fillColor: AppColors.fieldBackground,
    hintText: hintText,
    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: AppColors.border, width: 1),
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: AppColors.border, width: 1),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: AppColors.border, width: 1.2),
    ),
  );
}

/// Decoración para campos de solo lectura con fondo más oscuro
InputDecoration readOnlyFieldDecoration({String? hintText}) {
  return InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    filled: true,
    fillColor: const Color(0xFF1A1A2E), // Fondo más oscuro para indicar solo lectura
    hintText: hintText,
    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
    border: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
    ),
  );
}

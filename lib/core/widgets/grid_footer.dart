import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

class GridFooter extends StatelessWidget {
  final String text;
  const GridFooter({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.gridBackground,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

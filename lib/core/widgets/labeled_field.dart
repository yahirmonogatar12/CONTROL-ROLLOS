import 'package:flutter/material.dart';

class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  final Color? labelColor;

  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: labelColor ?? Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        child,
      ],
    );
  }
}

import 'package:flutter/material.dart';

class HorizontalField extends StatelessWidget {
  final String label;
  final Widget child;
  final double labelWidth;
  final Color? labelColor;

  const HorizontalField({
    super.key,
    required this.label,
    required this.child,
    this.labelWidth = 120,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: labelColor ?? Colors.white,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

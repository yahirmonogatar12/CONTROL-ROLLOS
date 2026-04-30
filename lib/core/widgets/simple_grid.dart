import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

class SimpleGridHeader extends StatelessWidget {
  final List<String> headers;

  const SimpleGridHeader({super.key, required this.headers});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: AppColors.gridHeader,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.6)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 26,
            child: Center(
              child: Icon(Icons.arrow_right, size: 14, color: Colors.white),
            ),
          ),
          Expanded(
            child: Row(
              children: headers
                  .map(
                    (h) => Expanded(
                      child: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: AppColors.border.withOpacity(0.6),
                            ),
                          ),
                        ),
                        child: Text(
                          h,
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class SimpleGrid extends StatelessWidget {
  final List<String> headers;

  const SimpleGrid({super.key, required this.headers});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SimpleGridHeader(headers: headers),
        const Expanded(
          child: Center(
            child: Text(
              'No data',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
        ),
      ],
    );
  }
}

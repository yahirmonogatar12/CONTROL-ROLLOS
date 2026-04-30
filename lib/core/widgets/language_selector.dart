import 'package:flutter/material.dart';
import 'package:material_warehousing_flutter/core/localization/app_translations.dart';
import 'package:material_warehousing_flutter/core/theme/app_colors.dart';

class LanguageSelector extends StatelessWidget {
  final LanguageProvider languageProvider;
  
  const LanguageSelector({super.key, required this.languageProvider});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            Text(
              _getLanguageLabel(languageProvider.currentLocale),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
          ],
        ),
      ),
      color: AppColors.panelBackground,
      onSelected: (String locale) {
        languageProvider.setLocale(locale);
      },
      itemBuilder: (BuildContext context) => [
        PopupMenuItem<String>(
          value: 'en',
          child: Row(
            children: [
              Text('🇺🇸', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text('English', style: TextStyle(color: Colors.white, fontSize: 13)),
              if (languageProvider.currentLocale == 'en')
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, color: Colors.green, size: 16),
                ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'es',
          child: Row(
            children: [
              Text('🇪🇸', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text('Español', style: TextStyle(color: Colors.white, fontSize: 13)),
              if (languageProvider.currentLocale == 'es')
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, color: Colors.green, size: 16),
                ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'ko',
          child: Row(
            children: [
              Text('🇰🇷', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text('한국어', style: TextStyle(color: Colors.white, fontSize: 13)),
              if (languageProvider.currentLocale == 'ko')
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, color: Colors.green, size: 16),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _getLanguageLabel(String locale) {
    switch (locale) {
      case 'es':
        return 'ES';
      case 'ko':
        return 'KO';
      default:
        return 'EN';
    }
  }
}

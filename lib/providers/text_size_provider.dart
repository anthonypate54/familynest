import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TextSizeOption { small, medium, large, extraLarge }

class TextSizeProvider extends ChangeNotifier {
  static const String _textSizeKey = 'text_size_option';

  TextSizeOption _textSizeOption = TextSizeOption.medium;

  TextSizeOption get textSizeOption => _textSizeOption;

  double get textScaleFactor {
    switch (_textSizeOption) {
      case TextSizeOption.small:
        return 0.85;
      case TextSizeOption.medium:
        return 1.0;
      case TextSizeOption.large:
        return 1.15;
      case TextSizeOption.extraLarge:
        return 1.30;
    }
  }

  String get textSizeDisplayName {
    switch (_textSizeOption) {
      case TextSizeOption.small:
        return 'Small';
      case TextSizeOption.medium:
        return 'Medium';
      case TextSizeOption.large:
        return 'Large';
      case TextSizeOption.extraLarge:
        return 'Extra Large';
    }
  }

  TextSizeProvider() {
    _loadTextSize();
  }

  // Load text size preference from storage
  Future<void> _loadTextSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final textSizeIndex =
          prefs.getInt(_textSizeKey) ?? TextSizeOption.medium.index;
      _textSizeOption = TextSizeOption.values[textSizeIndex];
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading text size preference: $e');
    }
  }

  // Set specific text size
  Future<void> setTextSize(TextSizeOption option) async {
    if (_textSizeOption != option) {
      _textSizeOption = option;
      await _saveTextSize();
      notifyListeners();
    }
  }

  // Save text size preference to storage
  Future<void> _saveTextSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_textSizeKey, _textSizeOption.index);
      debugPrint('Text size preference saved: ${textSizeDisplayName}');
    } catch (e) {
      debugPrint('Error saving text size preference: $e');
    }
  }
}

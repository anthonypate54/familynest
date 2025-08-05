import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

/// Simplified emoji picker widget for message composition
class EmojiPickerWidget extends StatelessWidget {
  final TextEditingController textController;
  final VoidCallback? onEmojiSelected;
  final bool isDarkMode;

  const EmojiPickerWidget({
    super.key,
    required this.textController,
    this.onEmojiSelected,
    this.isDarkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return EmojiPicker(
      textEditingController: textController,
      config: Config(
        height: 250,
        checkPlatformCompatibility: true,
        emojiViewConfig: EmojiViewConfig(
          backgroundColor: isDarkMode ? Colors.grey[900]! : Colors.white,
          columns: 7,
          emojiSizeMax: 28,
          gridPadding: const EdgeInsets.all(8),
          horizontalSpacing: 4,
          verticalSpacing: 4,
        ),
        categoryViewConfig: CategoryViewConfig(
          backgroundColor: isDarkMode ? Colors.grey[900]! : Colors.white,
          iconColor: isDarkMode ? Colors.grey[400]! : Colors.grey[600]!,
          iconColorSelected: Theme.of(context).primaryColor,
          initCategory: Category.SMILEYS,
        ),
        bottomActionBarConfig: BottomActionBarConfig(
          backgroundColor: isDarkMode ? Colors.grey[850]! : Colors.grey[100]!,
          enabled: true,
          showBackspaceButton: true,
        ),
        searchViewConfig: SearchViewConfig(
          backgroundColor: isDarkMode ? Colors.grey[900]! : Colors.white,
        ),
      ),
      onEmojiSelected: (Category? category, Emoji emoji) {
        debugPrint('🎉 Emoji selected: ${emoji.emoji}');
        onEmojiSelected?.call();
      },
    );
  }
}

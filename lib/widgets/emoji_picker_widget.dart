import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

/// Reusable emoji picker widget for message composition
class EmojiPickerWidget extends StatefulWidget {
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
  State<EmojiPickerWidget> createState() => _EmojiPickerWidgetState();
}

class _EmojiPickerWidgetState extends State<EmojiPickerWidget> {
  bool _showEmojiPicker = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Emoji picker (when visible)
        if (_showEmojiPicker)
          Container(
            height: 250,
            decoration: BoxDecoration(
              color: widget.isDarkMode ? Colors.grey[900] : Colors.white,
              border: Border(
                top: BorderSide(
                  color:
                      widget.isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                  width: 1,
                ),
              ),
            ),
            child: EmojiPicker(
              textEditingController: widget.textController,
              config: Config(
                height: 250,
                emojiViewConfig: EmojiViewConfig(
                  backgroundColor:
                      widget.isDarkMode ? Colors.grey[900]! : Colors.white,
                  columns: 7,
                  emojiSizeMax: 32,
                ),
                categoryViewConfig: CategoryViewConfig(
                  backgroundColor:
                      widget.isDarkMode ? Colors.grey[900]! : Colors.white,
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  backgroundColor:
                      widget.isDarkMode ? Colors.grey[850]! : Colors.grey[100]!,
                  enabled: true,
                ),
                searchViewConfig: SearchViewConfig(
                  backgroundColor:
                      widget.isDarkMode ? Colors.grey[900]! : Colors.white,
                ),
              ),
              onEmojiSelected: (Category? category, Emoji emoji) {
                debugPrint('🎉 Emoji selected: ${emoji.emoji}');
                // The emoji is automatically added to the text controller
                widget.onEmojiSelected?.call();
              },
            ),
          ),

        // Emoji toggle button row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              // Emoji button
              IconButton(
                icon: Icon(
                  _showEmojiPicker
                      ? Icons.keyboard
                      : Icons.emoji_emotions_outlined,
                  color:
                      _showEmojiPicker
                          ? Theme.of(context).primaryColor
                          : (widget.isDarkMode
                              ? Colors.grey[400]
                              : Colors.grey[600]),
                ),
                onPressed: _toggleEmojiPicker,
                tooltip: _showEmojiPicker ? 'Show Keyboard' : 'Show Emojis',
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });

    // Hide keyboard when showing emoji picker
    if (_showEmojiPicker) {
      FocusScope.of(context).unfocus();
    }
  }

  /// Public method to hide emoji picker (useful when sending message)
  void hideEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
    }
  }

  /// Public method to check if emoji picker is showing
  bool get isEmojiPickerVisible => _showEmojiPicker;
}

import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

/// Data class to hold emoji picker state
class EmojiPickerState {
  final bool isVisible;
  final Widget? emojiPickerWidget;

  const EmojiPickerState({required this.isVisible, this.emojiPickerWidget});
}

/// Reusable message input widget with emoji picker support
/// Returns an EmojiPickerState that the parent can use for bottomSheet
class EmojiMessageInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final VoidCallback onSend;
  final VoidCallback? onMediaAttach;
  final bool showMediaButton;
  final bool enabled;
  final bool isDarkMode;
  final Widget? sendButton;
  final EdgeInsets? padding;
  final ValueChanged<EmojiPickerState>? onEmojiPickerStateChanged;

  const EmojiMessageInput({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hintText,
    required this.onSend,
    this.onMediaAttach,
    this.showMediaButton = true,
    this.enabled = true,
    this.isDarkMode = false,
    this.sendButton,
    this.padding,
    this.onEmojiPickerStateChanged,
  });

  @override
  State<EmojiMessageInput> createState() => _EmojiMessageInputState();
}

class _EmojiMessageInputState extends State<EmojiMessageInput> {
  late FocusNode _focusNode;
  bool _showEmojiPicker = false;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    // Use provided focus node or create our own
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
  }

  @override
  void dispose() {
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });

    if (_showEmojiPicker) {
      // Hide keyboard when showing emoji picker
      FocusScope.of(context).unfocus();
    } else {
      // Show keyboard when hiding emoji picker
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
          widget.controller.selection = TextSelection.fromPosition(
            TextPosition(offset: widget.controller.text.length),
          );
        }
      });
    }

    // Notify parent about emoji picker state change
    _notifyEmojiPickerStateChanged();
  }

  void _onEmojiSelected() {
    debugPrint('🎉 Emoji selected, switching back to keyboard');
    // Hide emoji picker and show keyboard
    setState(() {
      _showEmojiPicker = false;
    });
    // Request focus to show keyboard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        widget.controller.selection = TextSelection.fromPosition(
          TextPosition(offset: widget.controller.text.length),
        );
      }
    });

    // Notify parent about emoji picker state change
    _notifyEmojiPickerStateChanged();
  }

  void _notifyEmojiPickerStateChanged() {
    if (widget.onEmojiPickerStateChanged != null) {
      final isDark =
          widget.isDarkMode || Theme.of(context).brightness == Brightness.dark;

      final emojiState = EmojiPickerState(
        isVisible: _showEmojiPicker,
        emojiPickerWidget:
            _showEmojiPicker
                ? Container(
                  height: 250,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                  ),
                  child: EmojiPicker(
                    textEditingController: widget.controller,
                    config: Config(
                      height: 250,
                      checkPlatformCompatibility: true,
                      emojiViewConfig: EmojiViewConfig(
                        backgroundColor:
                            isDark ? Colors.grey[900]! : Colors.white,
                        columns: 7,
                        emojiSizeMax: 28,
                        gridPadding: const EdgeInsets.all(8),
                        horizontalSpacing: 4,
                        verticalSpacing: 4,
                      ),
                      categoryViewConfig: CategoryViewConfig(
                        backgroundColor:
                            isDark ? Colors.grey[900]! : Colors.white,
                        iconColor:
                            isDark ? Colors.grey[400]! : Colors.grey[600]!,
                        iconColorSelected: Theme.of(context).primaryColor,
                        initCategory: Category.SMILEYS,
                      ),
                      bottomActionBarConfig: BottomActionBarConfig(
                        backgroundColor:
                            isDark ? Colors.grey[850]! : Colors.grey[100]!,
                        enabled: true,
                        showBackspaceButton: true,
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor:
                            isDark ? Colors.grey[900]! : Colors.white,
                      ),
                    ),
                    onEmojiSelected: (Category? category, Emoji emoji) {
                      debugPrint('🎉 Emoji selected: ${emoji.emoji}');
                      _onEmojiSelected();
                    },
                  ),
                )
                : null,
      );

      widget.onEmojiPickerStateChanged!(emojiState);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        widget.isDarkMode || Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: widget.padding ?? const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Media attachment button
            if (widget.showMediaButton && widget.onMediaAttach != null)
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.grey),
                onPressed: widget.enabled ? widget.onMediaAttach : null,
                tooltip: 'Attach Media',
              ),

            // Emoji button
            IconButton(
              icon: Icon(
                _showEmojiPicker
                    ? Icons.keyboard
                    : Icons.emoji_emotions_outlined,
                color:
                    _showEmojiPicker
                        ? Theme.of(context).primaryColor
                        : Colors.grey,
              ),
              onPressed: widget.enabled ? _toggleEmojiPicker : null,
              tooltip: _showEmojiPicker ? 'Show Keyboard' : 'Show Emojis',
            ),

            // Text input
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: widget.enabled ? (_) => widget.onSend() : null,
              ),
            ),

            const SizedBox(width: 8),

            // Send button
            widget.sendButton ??
                CircleAvatar(
                  backgroundColor:
                      widget.enabled && widget.controller.text.trim().isNotEmpty
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade400,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed:
                        widget.enabled &&
                                widget.controller.text.trim().isNotEmpty
                            ? widget.onSend
                            : null,
                    tooltip: 'Send Message',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For MaxLengthEnforcement
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:familynest/widgets/safe_text_field.dart';

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
  final bool mediaEnabled;
  final bool isDarkMode;
  final Widget? sendButton;
  final EdgeInsets? padding;
  final ValueChanged<EmojiPickerState>? onEmojiPickerStateChanged;
  final Function(String)? onPaste; // New callback for paste detection
  final int maxLength; // Maximum character length for messages

  const EmojiMessageInput({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hintText,
    required this.onSend,
    this.onMediaAttach,
    this.showMediaButton = true,
    this.enabled = true,
    this.mediaEnabled = true,
    this.isDarkMode = false,
    this.sendButton,
    this.padding,
    this.onEmojiPickerStateChanged,
    this.onPaste, // Add to constructor
    this.maxLength = 500, // Default to 500 characters
  });

  @override
  State<EmojiMessageInput> createState() => _EmojiMessageInputState();
}

class _EmojiMessageInputState extends State<EmojiMessageInput> {
  late FocusNode _focusNode;
  bool _showEmojiPicker = false;
  bool _ownsFocusNode = false;
  String _previousText = ''; // Store previous text to detect paste

  // Cache theme values to avoid unsafe lookups during state changes
  bool? _isDarkMode;
  Color? _surfaceColor;

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

    // Setup listener to detect paste events
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final currentText = widget.controller.text;

    // A paste event might have occurred if:
    // 1. Text length increased significantly (more than just typing one character)
    // 2. Contains a URL
    if (currentText.length > _previousText.length + 3) {
      // Check if the new text contains a URL
      if (currentText.contains('http://') || currentText.contains('https://')) {
        // Notify listener that a paste with URL has occurred
        if (widget.onPaste != null) {
          widget.onPaste!(currentText);
        }
      }
    }

    _previousText = currentText;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache theme values safely to avoid unsafe lookups during state changes
    final theme = Theme.of(context);
    _isDarkMode = widget.isDarkMode || theme.brightness == Brightness.dark;
    _surfaceColor = theme.colorScheme.surface;
  }

  @override
  void dispose() {
    // Remove listener to prevent memory leaks
    widget.controller.removeListener(_onTextChanged);

    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _openEmojiPicker() {
    setState(() {
      _showEmojiPicker = true;
    });
    // Hide keyboard when showing emoji picker
    FocusScope.of(context).unfocus();
    // Notify parent about emoji picker state change
    _notifyEmojiPickerStateChanged();
  }

  void _hideEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
      // Notify parent about emoji picker state change
      _notifyEmojiPickerStateChanged();
    }
  }

  void _onTextFieldTap() {
    // Google Messages style: Tap in text field always shows keyboard
    _hideEmojiPicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        widget.controller.selection = TextSelection.fromPosition(
          TextPosition(offset: widget.controller.text.length),
        );
      }
    });
  }

  void _onEmojiSelected() {
    // Hide emoji picker and show keyboard (Google Messages style)
    _hideEmojiPicker();
    // Request focus to show keyboard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        widget.controller.selection = TextSelection.fromPosition(
          TextPosition(offset: widget.controller.text.length),
        );
      }
    });
  }

  // Helper to check if text contains a URL
  bool _hasUrl(String text) {
    return text.contains('http://') || text.contains('https://');
  }

  void _notifyEmojiPickerStateChanged() {
    if (widget.onEmojiPickerStateChanged != null) {
      final isDark = _isDarkMode ?? false;

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
                        enabled:
                            false, // Remove the confusing bottom bar entirely
                        showBackspaceButton: false,
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor:
                            isDark ? Colors.grey[900]! : Colors.white,
                      ),
                    ),
                    onEmojiSelected: (Category? category, Emoji emoji) {
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
    final isDark = _isDarkMode ?? false;

    return Container(
      padding: widget.padding ?? const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: _surfaceColor ?? Colors.white,
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
                onPressed:
                    widget.enabled && widget.mediaEnabled
                        ? widget.onMediaAttach
                        : null,
                tooltip: 'Attach Media',
              ),

            // Emoji button (Google Messages style - just shows emoji picker)
            IconButton(
              icon: Icon(
                Icons.emoji_emotions_outlined,
                color:
                    _showEmojiPicker
                        ? Theme.of(context).primaryColor
                        : Colors.grey,
              ),
              onPressed: widget.enabled ? _openEmojiPicker : null,
              tooltip: 'Show Emojis',
            ),

            // Text input
            Expanded(
              child: SafeTextField(
                controller: widget.controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                maxLength: widget.maxLength,
                scrollable: true, // Enable scrolling for longer messages
                minLines: 1,
                maxLines: 5, // Limit visible lines to 5
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor:
                      _hasUrl(widget.controller.text)
                          ? (isDark
                              ? Colors.blue[900]
                              : Colors.blue[50]) // Highlight when URL detected
                          : (isDark ? Colors.grey[800] : Colors.white),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: widget.enabled ? (_) => widget.onSend() : null,
                onTap:
                    _onTextFieldTap, // Google Messages style: tap to show keyboard
                onChanged:
                    (_) => setState(
                      () {},
                    ), // Refresh UI when text changes to update URL highlighting
              ),
            ),

            const SizedBox(width: 8),

            // Send button
            widget.sendButton ??
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap:
                        widget.enabled &&
                                widget.controller.text.trim().isNotEmpty
                            ? widget.onSend
                            : null,
                    borderRadius: BorderRadius.circular(20),
                    child: CircleAvatar(
                      backgroundColor:
                          widget.enabled &&
                                  widget.controller.text.trim().isNotEmpty
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade400,
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(Icons.send, color: Colors.white),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

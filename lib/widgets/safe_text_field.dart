import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A TextField with built-in safety features like character limits
///
/// This widget extends the functionality of TextField while adding:
/// - Configurable character limits with enforcement
/// - Optional scrollable input for longer text
/// - Hidden character counter by default (can be shown if needed)
/// - Consistent styling and behavior across the app
class SafeTextField extends StatelessWidget {
  // Core properties from TextField
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool autofocus;
  final bool obscureText;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final Color? cursorColor;
  final bool? enableSuggestions;
  final bool? autocorrect;
  final TextInputAction? textInputAction;

  // SafeTextField specific properties
  final int maxLength;
  final bool showCounter;
  final bool scrollable;
  final int? minLines;
  final int? maxLines;

  // Callbacks
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;

  const SafeTextField({
    Key? key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.style,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.obscureText = false,
    this.enabled = true,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.sentences,
    this.cursorColor,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.textInputAction,
    this.maxLength = 500, // Default to 500 characters
    this.showCounter = false, // Hide counter by default
    this.scrollable = false, // Not scrollable by default
    this.minLines,
    this.maxLines = 1, // Single line by default
    this.onChanged,
    this.onSubmitted,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use the provided maxLines value regardless of scrollable
    final effectiveMaxLines = maxLines;

    // Determine actual minLines based on scrollable property
    final effectiveMinLines = scrollable ? (minLines ?? 1) : minLines;

    // Determine effective keyboardType
    final effectiveKeyboardType =
        scrollable
            ? TextInputType.multiline
            : (keyboardType ?? TextInputType.text);

    // Create effective decoration with counter handling
    final effectiveDecoration = (decoration ?? const InputDecoration())
        .copyWith(counterText: showCounter ? null : '');

    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: effectiveDecoration,
      keyboardType: effectiveKeyboardType,
      style: style,
      textAlign: textAlign,
      autofocus: autofocus,
      obscureText: obscureText,
      enabled: enabled,
      maxLength: maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      minLines: effectiveMinLines,
      maxLines: effectiveMaxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      textCapitalization: textCapitalization,
      cursorColor: cursorColor,
      enableSuggestions: enableSuggestions,
      autocorrect: autocorrect,
      textInputAction: textInputAction,
    );
  }
}

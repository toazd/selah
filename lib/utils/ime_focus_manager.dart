// Create a separate file: lib/utils/ime_focus_manager.dart
import 'package:flutter/material.dart';

/// Forcing the focus to a transparent button helps to circumvent the focus issues
/// with OSK on desktop Windows touchscreen devices when no keyboard is attached.
///
/// The bug occurs when the user enters any TextField and does not exit the keyboard
/// with the enter button but instead closes the OSK with the X, and then attempts
/// to navigate anywhere else. After the bug is triggered, the OSK will pop up
/// for actions that it shouldn't (like tapping an AppBar icon).
///
/// This method fixes that problem by forcing the focus to a transparent
/// ElevatedButton at key points which forcefully removes the focus from the TextField.
///
/// Normal Unfocus attempts such as:
/// FocusManager.instance.primaryFocus?.unfocus();
/// FocusScope.of(context).requestFocus(FocusNode());
/// will not work so don't bother with them.
class ImeFocusManager {
  static final GlobalKey<State> _buttonKey = GlobalKey();
  static FocusNode? _focusNode;
  static bool _isInitialized = false;

  // Initialize the focus system
  static void initialize() {
    if (_isInitialized) return;
    _focusNode = FocusNode();
    _isInitialized = true;
  }

  // Get the transparent button widget
  static Widget getTransparentButton() {
    initialize();
    return Semantics(
      button: true,
      focusable: true,
      child: ExcludeSemantics(
        child: ElevatedButton(
          key: _buttonKey,
          focusNode: _focusNode,
          onPressed: () {}, // Empty handler
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            side: BorderSide.none,
            padding: EdgeInsets.zero,
            minimumSize: Size(1, 1), // Minimum clickable area
          ),
          child: SizedBox.shrink(), // Completely invisible
        ),
      ),
    );
  }

  // Request focus programmatically
  static void requestFocus() {
    if (!_isInitialized || _focusNode == null) return;

    // Use Future.delayed to ensure the widget is built
    Future.delayed(Duration(milliseconds: 10), () {
      if (_focusNode?.canRequestFocus ?? false) {
        _focusNode!.requestFocus();
      }
    });
  }

  // Clear focus
  static void clearFocus() {
    _focusNode?.unfocus();
  }

  // Check if has focus
  static bool get hasFocus => _focusNode?.hasFocus ?? false;

  // Dispose
  static void dispose() {
    _focusNode?.dispose();
    _focusNode = null;
    _isInitialized = false;
  }
}

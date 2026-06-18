import 'package:flutter/material.dart';

/// A text widget that automatically adjusts its font size to fit within the available width.
/// Uses TextPainter to measure text dimensions and reduces font size incrementally until
/// the text fits within the available constraints. Used by search AppBars to ensure
/// that result totals fit on narrow screens while responding to window size changes.
class ResponsiveText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double minFontSize;
  final double stepSize;
  final int? maxLines;
  final TextOverflow overflow;

  const ResponsiveText({
    super.key,
    required this.text,
    required this.style,
    this.minFontSize = 4.0,
    this.stepSize = 1.0,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  State<ResponsiveText> createState() {
    return _ResponsiveTextState();
  }
}

class _ResponsiveTextState extends State<ResponsiveText> {
  double _calculateOptimalFontSizeSync(
      String text, TextStyle style, double maxWidth) {
    // Start with the desired font size
    double currentSize = style.fontSize ?? 14.0;

    // Create TextPainter for measurement
    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: widget.maxLines,
    );

    // Try font sizes from largest to smallest
    while (currentSize >= widget.minFontSize) {
      textPainter.text = TextSpan(
        text: text,
        style: style.copyWith(fontSize: currentSize),
      );
      textPainter.layout(
          maxWidth: double.infinity); // Using infinity to get natural width

      // Check if text fits within available width
      if (textPainter.width <= maxWidth) {
        return currentSize;
      }

      // Try smaller font size
      currentSize -= widget.stepSize;
    }

    // If we hit minimum size and still don't fit, use minimum size anyway

    return widget.minFontSize;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate font size synchronously without setState()
        final optimalFontSize = _calculateOptimalFontSizeSync(
          widget.text,
          widget.style,
          constraints.maxWidth,
        );

        return Text(
          widget.text,
          style: widget.style.copyWith(fontSize: optimalFontSize),
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          softWrap: widget.maxLines != 1,
        );
      },
    );
  }
}

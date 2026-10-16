import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../utils/preferences_constants.dart';
import '../utils/verse_reference_detector.dart';

/// Renders the small subset of HTML used by the Webster's 1828 definitions.
///
/// The source data only needs bold, italic, line breaks, and links. Keeping
/// this renderer local avoids bringing a full HTML widget into the app just
/// for those four tags, while retaining the link behavior used by the old
/// renderer.
class WebstersDefinitionRenderer extends StatefulWidget {
  final String data;
  final void Function(String url, String referenceText)? onLinkTap;

  const WebstersDefinitionRenderer({
    super.key,
    required this.data,
    this.onLinkTap,
  });

  @override
  State<WebstersDefinitionRenderer> createState() =>
      _WebstersDefinitionRendererState();
}

class _WebstersDefinitionRendererState
    extends State<WebstersDefinitionRenderer> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseStyle = TextStyle(
      fontSize: uiFontSize,
      fontFamily: fontFamilyNotifier.value,
      color: isDark ? darkTextColor.value : lightTextColor.value,
      height: 1.5,
    );
    final root = _parse(widget.data);

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: _buildChildren(
          root,
          baseStyle,
        ),
      ),
    );
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  List<InlineSpan> _buildChildren(
    _HtmlNode node,
    TextStyle inheritedStyle, {
    String? link,
    String? referenceText,
  }) {
    final spans = <InlineSpan>[];

    for (final child in node.children) {
      if (child.text != null) {
        spans.addAll(
          _buildTextSpans(
            child.text!,
            inheritedStyle,
            link: link,
            referenceText: referenceText,
          ),
        );
        continue;
      }

      if (child.tag == 'br') {
        spans.add(TextSpan(text: '\n', style: inheritedStyle));
        continue;
      }

      var childStyle = inheritedStyle;
      if (child.tag == 'b') {
        childStyle = childStyle.copyWith(fontWeight: FontWeight.bold);
      } else if (child.tag == 'i') {
        childStyle = childStyle.copyWith(fontStyle: FontStyle.italic);
      }

      var childLink = link;
      var childReferenceText = referenceText;
      if (child.tag == 'a') {
        childLink = child.attributes['href'];
        childReferenceText =
            child.attributes['data-reference-text'] ?? _plainText(child).trim();
        if (childLink != null) {
          childLink = _decodeHtmlEntities(childLink);
        }
      }

      spans.addAll(
        _buildChildren(
          child,
          childStyle,
          link: childLink,
          referenceText: childReferenceText,
        ),
      );
    }

    return spans;
  }

  List<InlineSpan> _buildTextSpans(
    String rawText,
    TextStyle inheritedStyle, {
    String? link,
    String? referenceText,
  }) {
    final text = _decodeHtmlEntities(rawText);
    if (text.isEmpty) return const [];

    final linkStyle = inheritedStyle.copyWith(
      color: Colors.blue,
      decoration: TextDecoration.underline,
    );

    if (link != null) {
      return [
        _linkSpan(
          text,
          linkStyle,
          link,
          referenceText ?? text,
        ),
      ];
    }

    final references = VerseReferenceDetector.detectReferences(text).toList()
      ..sort((a, b) {
        final startCompare = a.startIndex.compareTo(b.startIndex);
        if (startCompare != 0) return startCompare;
        return b.originalText.length.compareTo(a.originalText.length);
      });

    final spans = <InlineSpan>[];
    var currentIndex = 0;
    for (final reference in references) {
      if (reference.startIndex < currentIndex) continue;

      spans.add(
        TextSpan(
          text: text.substring(currentIndex, reference.startIndex),
          style: inheritedStyle,
        ),
      );
      final end = reference.startIndex + reference.originalText.length;
      spans.add(
        _linkSpan(
          reference.originalText,
          linkStyle,
          _verseLinkForReference(reference),
          reference.originalText,
        ),
      );
      currentIndex = end;
    }

    spans.add(
      TextSpan(
        text: text.substring(currentIndex),
        style: inheritedStyle,
      ),
    );
    return spans;
  }

  TextSpan _linkSpan(
    String text,
    TextStyle style,
    String url,
    String referenceText,
  ) {
    if (widget.onLinkTap == null) {
      return TextSpan(text: text, style: style);
    }

    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onLinkTap!(url, referenceText);
    _recognizers.add(recognizer);
    return TextSpan(
      text: text,
      style: style,
      recognizer: recognizer,
      mouseCursor: SystemMouseCursors.click,
    );
  }

  String _verseLinkForReference(VerseReference reference) {
    var verseSpec = '';
    final colonIndex = reference.originalText.indexOf(':');
    if (colonIndex != -1 && colonIndex + 1 < reference.originalText.length) {
      verseSpec = reference.originalText
          .substring(colonIndex + 1)
          .replaceAll(RegExp(r'\s+'), '');
    }

    if (verseSpec.isEmpty && reference.endVerse != null) {
      verseSpec = '${reference.verse}-${reference.endVerse}';
    } else if (verseSpec.isEmpty) {
      verseSpec = reference.verse.toString();
    }

    return 'v://${reference.book}/${reference.chapter}/$verseSpec';
  }
}

class _HtmlNode {
  final String? tag;
  final String? text;
  final Map<String, String> attributes;
  final List<_HtmlNode> children = [];

  _HtmlNode.root()
      : tag = null,
        text = null,
        attributes = const {};

  _HtmlNode.element(this.tag, this.attributes) : text = null;

  _HtmlNode.text(this.text)
      : tag = null,
        attributes = const {};
}

_HtmlNode _parse(String html) {
  final root = _HtmlNode.root();
  final stack = <_HtmlNode>[root];
  var index = 0;

  while (index < html.length) {
    final tagStart = html.indexOf('<', index);
    if (tagStart == -1) {
      _addText(stack.last, html.substring(index));
      break;
    }

    if (tagStart > index) {
      _addText(stack.last, html.substring(index, tagStart));
    }

    final tagEnd = _findTagEnd(html, tagStart + 1);
    if (tagEnd == -1) {
      _addText(stack.last, html.substring(tagStart));
      break;
    }

    final source = html.substring(tagStart + 1, tagEnd).trim();
    final match = RegExp(r'^(/?)\s*([A-Za-z][A-Za-z0-9:-]*)([\s\S]*)$')
        .firstMatch(source);
    if (match == null) {
      _addText(stack.last, html.substring(tagStart, tagEnd + 1));
      index = tagEnd + 1;
      continue;
    }

    final isClosing = match.group(1) == '/';
    final tag = match.group(2)!.toLowerCase();
    final remainder = match.group(3) ?? '';
    if (isClosing) {
      _closeTag(stack, tag);
    } else if (tag == 'br') {
      stack.last.children.add(_HtmlNode.element('br', const {}));
    } else {
      final node = _HtmlNode.element(tag, _parseAttributes(remainder));
      stack.last.children.add(node);
      if (!remainder.trimRight().endsWith('/')) {
        stack.add(node);
      }
    }

    index = tagEnd + 1;
  }

  return root;
}

void _addText(_HtmlNode node, String text) {
  if (text.isNotEmpty) node.children.add(_HtmlNode.text(text));
}

int _findTagEnd(String html, int start) {
  String? quote;
  for (var index = start; index < html.length; index++) {
    final character = html[index];
    if (quote != null) {
      if (character == quote) quote = null;
    } else if (character == '"' || character == "'") {
      quote = character;
    } else if (character == '>') {
      return index;
    }
  }
  return -1;
}

Map<String, String> _parseAttributes(String source) {
  final attributes = <String, String>{};
  final pattern = RegExp(
    r'''([A-Za-z][A-Za-z0-9:_-]*)\s*=\s*(?:"([\s\S]*?)"|'([\s\S]*?)'|([^\s>]+))''',
  );
  for (final match in pattern.allMatches(source)) {
    attributes[match.group(1)!.toLowerCase()] =
        match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
  }
  return attributes;
}

void _closeTag(List<_HtmlNode> stack, String tag) {
  for (var index = stack.length - 1; index > 0; index--) {
    if (stack[index].tag == tag) {
      stack.removeRange(index, stack.length);
      return;
    }
  }
}

String _plainText(_HtmlNode node) {
  if (node.text != null) return _decodeHtmlEntities(node.text!);
  if (node.tag == 'br') return '\n';
  return node.children.map(_plainText).join();
}

String _decodeHtmlEntities(String value) {
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

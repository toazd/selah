import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import '../main.dart';
import '../utils/font_size_adjustments.dart';
import '../utils/preferences_constants.dart';

class TskReferenceDisplay extends StatefulWidget {
  // TSK data is a semicolon-delimited list of spec tokens like
  // "Pro/8/22-24;Pro/16/4".
  final String noteText;
  final Function(String, String?)? onLinkTap;

  const TskReferenceDisplay({
    super.key,
    required this.noteText,
    this.onLinkTap,
  });

  @override
  State<TskReferenceDisplay> createState() => _TskReferenceDisplayState();
}

class _TskReferenceDisplayState extends State<TskReferenceDisplay> {
  static const int _maxCachedEntries = 256;
  static const int _maxRecognizerPoolSize = 1000;
  static final LinkedHashMap<String, List<_TskSpecToken>> _tokenCache =
      LinkedHashMap<String, List<_TskSpecToken>>();
  static final List<TapGestureRecognizer> _recognizerPool = [];

  late List<_TskSpecToken> _tokens;
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuildParsedContent();
  }

  @override
  void didUpdateWidget(covariant TskReferenceDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteText != widget.noteText ||
        oldWidget.onLinkTap != widget.onLinkTap) {
      _rebuildParsedContent();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _rebuildParsedContent() {
    _disposeRecognizers();
    _tokens = _getCachedTokens(widget.noteText);

    for (final token in _tokens) {
      // Reuse recognizer from pool if available, otherwise create new
      final recognizer = _recognizerPool.isNotEmpty
          ? _recognizerPool.removeLast()
          : TapGestureRecognizer();

      recognizer.onTap =
          () => widget.onLinkTap?.call(token.link, token.displayText);
      _recognizers.add(recognizer);
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.onTap = null;
      // Return recognizer to pool instead of disposing
      if (_recognizerPool.length < _maxRecognizerPoolSize) {
        _recognizerPool.add(recognizer);
      } else {
        recognizer.dispose();
      }
    }
    _recognizers.clear();
  }

  List<_TskSpecToken> _getCachedTokens(String noteText) {
    final cached = _tokenCache.remove(noteText);
    if (cached != null) {
      _tokenCache[noteText] = cached;
      return cached;
    }

    final parsed = _parseTokens(noteText);
    _tokenCache[noteText] = parsed;
    if (_tokenCache.length > _maxCachedEntries) {
      _tokenCache.remove(_tokenCache.keys.first);
    }
    return parsed;
  }

  List<_TskSpecToken> _parseTokens(String noteText) {
    if (noteText.trim().isEmpty) {
      return const [];
    }

    final tokens = <_TskSpecToken>[];
    for (final rawToken in noteText.split(';')) {
      final token = rawToken.trim();
      if (token.isEmpty) {
        continue;
      }

      final firstSlash = token.indexOf('/');
      final secondSlash =
          firstSlash == -1 ? -1 : token.indexOf('/', firstSlash + 1);

      if (firstSlash <= 0 ||
          secondSlash <= firstSlash + 1 ||
          secondSlash >= token.length - 1) {
        continue;
      }

      final book = token.substring(0, firstSlash);
      final chapter = token.substring(firstSlash + 1, secondSlash);
      final verseSpec = token.substring(secondSlash + 1);

      tokens.add(
        _TskSpecToken(
          book: book,
          chapter: chapter,
          verseSpec: verseSpec,
        ),
      );
    }

    return List.unmodifiable(tokens);
  }

  TextStyle _effectiveTskStyle(String fontFamily) {
    final desktopFontAdjustment =
        !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

    return TextStyle(
      // Make the font size slightly smaller
      fontSize: FontSizeAdjustments.getAdjustedSize(
        fontFamily,
        desktopFontAdjustment
            ? fontSizeNotifier.value - fontSizeAdjustmentDesktop
            : fontSizeNotifier.value - fontSizeAdjustmentMobile,
      ),
      fontFamily: fontFamily,
      color: Theme.of(context).brightness == Brightness.dark
          ? darkTextColor.value
          : lightTextColor.value,
      height: defaultLineHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Outer AnimatedBuilder for layout-affecting changes (font size, family)
    return AnimatedBuilder(
      animation: Listenable.merge([
        noteFontFamilyNotifier,
        fontSizeNotifier,
      ]),
      builder: (context, child) {
        if (_tokens.isEmpty) {
          return const SizedBox.shrink();
        }

        final fontFamily = noteFontFamilyNotifier.value;
        final baseStyle = _effectiveTskStyle(fontFamily);
        final strutStyle = StrutStyle.fromTextStyle(
          baseStyle,
          forceStrutHeight: true,
        );

        // Inner AnimatedBuilder for color-only changes
        return AnimatedBuilder(
          animation: Listenable.merge([
            lightTextColor,
            darkTextColor,
            lightVerseReferenceColor,
            darkVerseReferenceColor,
          ]),
          builder: (context, child) {
            final linkStyle = baseStyle.copyWith(
              color: Theme.of(context).brightness == Brightness.dark
                  ? darkVerseReferenceColor.value
                  : lightVerseReferenceColor.value,
              decoration: TextDecoration.none,
            );

            int linkIndex = 0;
            final children = <InlineSpan>[];

            for (int i = 0; i < _tokens.length; i++) {
              final token = _tokens[i];
              final recognizer = _recognizers[linkIndex++];

              children.add(
                TextSpan(
                  text: token.displayText,
                  style: linkStyle,
                  recognizer: recognizer,
                  mouseCursor: SystemMouseCursors.click,
                ),
              );

              if (i < _tokens.length - 1) {
                children.add(TextSpan(text: ', ', style: baseStyle));
              }
            }

            return RichText(
              textScaler: MediaQuery.textScalerOf(context),
              softWrap: true,
              strutStyle: strutStyle,
              text: TextSpan(style: baseStyle, children: children),
            );
          },
        );
      },
    );
  }
}

@immutable
class _TskSpecToken {
  final String book;
  final String chapter;
  final String verseSpec;

  const _TskSpecToken({
    required this.book,
    required this.chapter,
    required this.verseSpec,
  });

  String get displayText {
    return '$book $chapter:$verseSpec';
  }

  String get link {
    return 'v://$book/$chapter/$verseSpec';
  }
}

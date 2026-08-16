import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(const PreviewApp());

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Your newly formatted markdown and XML hybrid string block
    const String sampleDefinition =
        "**אָב** (ʼâb | awb)\n**Derivation: **a primitive word;\n**Strongs: **father, in a literal and immediate, or figurative and remote application\n**KJV: **chief, (fore-) father(-less), [idiom] patrimony, principal. Compare names in 'Abi-'.\n\n**Cognate Group:** H44 (Abiezer), H21 (Abi), H43 (Ebiasaph), H23 (Abiasaph), H372 (Jeezer), H42 (Abinoam), H36 (Abitub), H51 (Abishur), H32 (Abihail), H49 (Abishag), H31 (Abihud), H53 (Abishalom), H27 (Abidan), H45 (Abialbon), H40 (Abimelech), H38 (Abijam), H30 (Abihu), H28 (Abida), H26 (Abigal), H54 (Abiathar), H85 (Abraham), H1 (chief), H33 (Abiezrite), H52 (Abishai), H373 (Jezerite), H39 (Abimael), H22 (Abiel), H37 (Abital), H48 (Abiram), H87 (Abram), H41 (Abinadab), H29 (Abiah), H74 (Abner), H50 (Abishua)";

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        //appBar: AppBar(title: const Text('Definition Live Preview')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Builder(
            builder: (context) {
              // 2. We render the string using our high-performance parser
              return parseAndRenderDefinition(
                context,
                sampleDefinition,
                onStrongsTapped: (strongsId) {
                  // This is the interactive callback triggered by tapping a link
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Popup definition requested for: $strongsId'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // High-performance string token parser
  Widget parseAndRenderDefinition(
    BuildContext context,
    String rawText, {
    required Function(String id) onStrongsTapped,
  }) {
    // Regex splits by bold (**), italic (*), and any tag tokens (<tag>...</tag>)
    final RegExp exp = RegExp(r'(\*\*.*?\*\*|\*.*?\*|<[^>]+>.*?</[^>]+>)');
    final Iterable<RegExpMatch> matches = exp.allMatches(rawText);

    List<InlineSpan> spans = [];
    int lastMatchEnd = 0;

    for (final match in matches) {
      // Add plain unformatted text leading up to the match
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: rawText.substring(lastMatchEnd, match.start)));
      }

      final String matchText = match.group(0)!;

      if (matchText.startsWith('**') && matchText.endsWith('**')) {
        // Handle bold blocks
        spans.add(TextSpan(
          text: matchText.substring(2, matchText.length - 2),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ));
      } else if (matchText.startsWith('*') && matchText.endsWith('*')) {
        // Handle italic blocks
        spans.add(TextSpan(
          text: matchText.substring(1, matchText.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (matchText.startsWith('<hebrew>') && matchText.endsWith('</hebrew>')) {
        // Handle Hebrew blocks
        spans.add(TextSpan(
          text: matchText.substring(8, matchText.length - 9),
          style: const TextStyle(
            fontSize: 22.0, // Hebrew is easier to read when slightly larger
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
          ),
        ));
      } else if (matchText.startsWith('<greek>') && matchText.endsWith('</greek>')) {
        // Handle Greek blocks
        spans.add(TextSpan(
          text: matchText.substring(7, matchText.length - 8),
          style: const TextStyle(fontSize: 18.0, fontStyle: FontStyle.italic),
        ));
      } else if (matchText.startsWith('<link>') && matchText.endsWith('</link>')) {
        // Extract raw Strong's text identifier
        final String strongsId = matchText.substring(6, matchText.length - 7);

        // Handle interactive links
        spans.add(TextSpan(
          text: strongsId,
          style: const TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => onStrongsTapped(strongsId),
        ));
      }

      lastMatchEnd = match.end;
    }

    // Add any remaining trailing text
    if (lastMatchEnd < rawText.length) {
      spans.add(TextSpan(text: rawText.substring(lastMatchEnd)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 16.0, height: 1.5, color: Colors.black87),
        children: spans,
      ),
    );
  }
}

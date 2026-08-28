import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:selah/utils/note_storage_format.dart';

void main() {
  test('normalizes legacy Strong\'s links without changing note content', () {
    final note = jsonEncode([
      {
        'insert': 'H123',
        'attributes': {'link': 'strongs://H123', 'bold': true},
      },
      {'insert': ' and '},
      {
        'insert': 'G456',
        'attributes': {'link': 's://G456'},
      },
    ]);

    final normalized =
        jsonDecode(NoteStorageFormat.normalizeLegacyStrongsLinks(note)) as List;

    expect(normalized[0]['insert'], 'H123');
    expect(normalized[0]['attributes'], {
      'link': 's://H123',
      'bold': true,
    });
    expect(normalized[1]['insert'], ' and ');
    expect(normalized[2]['attributes']['link'], 's://G456');
  });

  test('converts legacy plain text to Delta', () {
    final normalized = NoteStorageFormat.normalizeLegacyStrongsLinks('A note');

    expect(jsonDecode(normalized), [
      {'insert': 'A note'},
    ]);
  });
}

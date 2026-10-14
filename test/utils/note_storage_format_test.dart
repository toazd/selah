import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:selah/utils/note_storage_format.dart';

void main() {
  test('converts legacy plain text to Delta', () {
    final normalized = NoteStorageFormat.ensureDeltaFormat('A note');

    expect(jsonDecode(normalized), [
      {'insert': 'A note'},
    ]);
  });
}

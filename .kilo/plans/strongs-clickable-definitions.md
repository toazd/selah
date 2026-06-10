# Strong's definition clickable links plan

## Goal

Add a Strong's definition data wrapper and make Strong's numbers clickable in the Strong's summary and verse result areas of `lib/screens/strongs_search_screen.dart`. Tapping a clickable Strong's number opens a dialog displaying the formatted definition from `lib/data/strongs_definitions.dart`.

## Scope

### Files to change

- `lib/database/strongs_definitions_database.dart`
  - New wrapper around `lib/data/strongs_definitions.dart`.
- `lib/screens/strongs_search_screen.dart`
  - Import the new wrapper.
  - Make Strong's numbers in the Strong's summary clickable.
  - Make Strong's numbers in verse results clickable.
  - Add a definition dialog with markdown-style bold/italic formatting.

### Files not to change

- `lib/data/strongs_definitions.dart`
  - The data file format should remain unchanged.
- Phrase summary rendering
  - The phrase summary intentionally does not display Strong's numbers, so it should not be modified for Strong's links.

## Implementation details

### 1. Add `StrongsDefinitionsDatabase`

Create `lib/database/strongs_definitions_database.dart` with a static helper class similar in style to the existing database wrappers.

Recommended API:

```dart
static String? getDefinition(String strongsNumber)
```

Behavior:

- Accept strings such as `H1234` or `G4544`.
- Normalize the prefix to uppercase.
- Parse the numeric suffix with `int.tryParse`.
- Return the matching value from `strongsDefinitions`.
- Return `null` for invalid prefixes, invalid numbers, or missing definitions.

Optional helper:

```dart
static bool isValidStrongsDefinitionNumber(String strongsNumber)
```

This can be useful for avoiding unnecessary dialog attempts.

### 2. Add Strong's definition dialog to `StrongsSearchScreen`

Add a private method:

```dart
void _showStrongsDefinitionDialog(BuildContext context, String strongsNumber)
```

Behavior:

- Call `StrongsDefinitionsDatabase.getDefinition(strongsNumber)`.
- If the definition is `null`, show a short styled snackbar such as `Definition not found for H1234`.
- Otherwise, call `showDialog` with an `AlertDialog`.
- Use a large scrollable content area because definitions can be long.
- Title the dialog with the Strong's number.
- Add a simple `Close` action.

### 3. Format definition text

Add a private formatter for the markdown-like definition text.

Recommended approach:

- Split the definition on `\n`.
- Render blank lines as vertical spacing.
- Render non-blank lines with `RichText`/`TextSpan`.
- Parse inline markers:
  - `**bold text**` → bold `TextSpan`
  - `*italic text*` → italic `TextSpan`
- Process `**` before `*` so bold markers are not accidentally split into italic markers.
- Preserve unmatched asterisks as literal text to avoid corrupting malformed notes.

Example helper shape:

```dart
List<InlineSpan> _buildDefinitionSpans(
  BuildContext context,
  String line,
  TextStyle baseStyle,
)
```

The dialog content should be:

```dart
SingleChildScrollView(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ...formatted definition lines/spacers...
    ],
  ),
)
```

### 4. Make Strong's summary links clickable

In `_buildStrongNumbersTableSection`, the middle cell currently renders:

```dart
Text(entry.key, style: snStyle, textAlign: TextAlign.center)
```

Replace it with a tappable widget, for example:

```dart
MouseRegion(
  cursor: SystemMouseCursors.click,
  child: GestureDetector(
    onTap: () => _showStrongsDefinitionDialog(context, entry.key),
    child: Text(entry.key, style: snStyle.copyWith(color: primary color), textAlign: TextAlign.center),
  ),
)
```

Use the existing primary color helper for both light and dark themes.

### 5. Make verse Strong's numbers clickable

The verse Strong's numbers are currently built inside `_buildVerseSpan` as non-clickable `WidgetSpan` children.

Add a helper such as:

```dart
WidgetSpan _buildClickableStrongsSpan(
  BuildContext context,
  String strongsNumber,
  double baseFontSize,
  double fontSize,
  Color color,
)
```

Behavior:

- Wrap the translated superscript `Text` in `GestureDetector`.
- Add `MouseRegion` for desktop click cursor.
- On tap, call `_showStrongsDefinitionDialog(context, strongsNumber)`.
- Preserve the existing superscript transform and sizing.

Replace the existing verse Strong's number `WidgetSpan` construction in both matched-tag and standalone-tag branches with this helper.

### 6. Preserve existing verse reference behavior

Do not reuse or disturb the existing `TapGestureRecognizer` logic for verse references. Strong's definition links should use independent `GestureDetector`/`MouseRegion` wrapping so the existing verse reference cleanup remains unchanged.

## Validation

After implementation, run syntax-focused validation only:

```bash
dart format lib/database/strongs_definitions_database.dart lib/screens/strongs_search_screen.dart
flutter analyze
```

No functional test suite is required unless `flutter analyze` exposes issues that need targeted correction.

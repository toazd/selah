import 'package:material_ui/material_ui.dart';
import 'package:selah/utils/preferences_constants.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

SnackBar _buildStyledSnackBar(String message, {bool isError = false}) {
  Color? textColor;
  if (isError) {
    textColor = Colors.red;
  } else {
    textColor = Colors.white;
  }

  return SnackBar(
    duration: const Duration(seconds: 3),
    backgroundColor: Colors.blueGrey,
    content: Text(
      message,
      style: TextStyle(
        fontSize: uiFontSize + 4,
        fontFamily: uiFontFamily,
        color: textColor,
      ),
      textAlign: TextAlign.center,
    ),
  );
}

/// "Global" snackbar replacement that handles formatting so all the snackbar messages
/// in the app are consistent.
void showStyledSnackBar(BuildContext context, String message,
    {bool isError = false}) {
  ScaffoldMessenger.of(context)
      .showSnackBar(_buildStyledSnackBar(message, isError: isError));
}

/// Only used by the error_handler.dart since it doesn't have a context.
/// Use showStyledSnackBar instead.
void showStyledSnackBarGlobal(String message, {bool isError = false}) {
  scaffoldMessengerKey.currentState
      ?.showSnackBar(_buildStyledSnackBar(message, isError: isError));
}

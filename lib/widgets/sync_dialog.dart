import 'package:flutter/material.dart';
import '../utils/preferences_constants.dart';

class SyncDialog extends StatelessWidget {
  const SyncDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Syncing data...',
            style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

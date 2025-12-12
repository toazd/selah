// Example file showing how to test the tablet mode detection utility.
//
// This file demonstrates how to use the TabletModeDetector class with debugPrint
// statements for testing purposes.

import 'package:flutter/material.dart';
import 'tablet_mode_detector.dart';

/// Example function to test tablet mode detection
Future<void> testTabletModeDetection() async {
  try {
    // Test individual functions
    final isTablet = await TabletModeDetector.isTabletMode();
    final hasKeyboard = await TabletModeDetector.isKeyboardAttached();
    final hasTouch = await TabletModeDetector.hasTouchScreen();
    final maxTouchPoints = await TabletModeDetector.getMaximumTouchPoints();
    final isConvertible = await TabletModeDetector.isConvertibleDevice();

    debugPrint('=== Tablet Mode Detection Test Results ===');
    debugPrint('Is Tablet Mode: $isTablet');
    debugPrint('Has Keyboard Attached: $hasKeyboard');
    debugPrint('Has Touch Screen: $hasTouch');
    debugPrint('Maximum Touch Points: $maxTouchPoints');
    debugPrint('Is Convertible Device: $isConvertible');

    // Test comprehensive device info
    final deviceInfo = await TabletModeDetector.getDeviceInfo();
    debugPrint('=== Comprehensive Device Info ===');
    deviceInfo.forEach((key, value) {
      debugPrint('$key: $value');
    });

    // Example of how you might use this in your app logic
    if (isTablet) {
      debugPrint('📱 Device is in tablet mode - optimize UI for touch');
    } else {
      debugPrint('💻 Device is in desktop mode - optimize UI for keyboard/mouse');
    }

    if (!hasKeyboard) {
      debugPrint('⚠️ No keyboard detected - consider showing virtual keyboard');
    }
  } catch (e) {
    debugPrint('❌ Error testing tablet mode detection: $e');
  }
}

/// Example widget that shows tablet mode information
class TabletModeInfoWidget extends StatelessWidget {
  const TabletModeInfoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: TabletModeDetector.getDeviceInfo(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        }

        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }

        final deviceInfo = snapshot.data ?? {};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device Information:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Tablet Mode: ${deviceInfo['isTabletMode'] ?? 'Unknown'}'),
            Text('Keyboard Attached: ${deviceInfo['isKeyboardAttached'] ?? 'Unknown'}'),
            Text('Touch Screen: ${deviceInfo['hasTouchScreen'] ?? 'Unknown'}'),
            Text('Max Touch Points: ${deviceInfo['maxTouchPoints'] ?? 'Unknown'}'),
          ],
        );
      },
    );
  }
}

/// Example of how to call the test function from your main app
void setupTabletModeTesting() {
  // You can call this from your main() function or initState()
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await testTabletModeDetection();
  });
}

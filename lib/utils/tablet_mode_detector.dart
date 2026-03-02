import 'package:flutter/foundation.dart';
import 'tablet_mode_method_channel.dart';
import 'tablet_mode_platform_interface.dart';
import 'error_handler.dart';

/// Utility class for detecting tablet mode and device capabilities.
///
/// This class provides a simple API for checking if a device is in tablet mode,
/// has a keyboard attached, or has touch screen capabilities.
class TabletModeDetector {
  static TabletModePlatform _platform = MethodChannelTabletMode();

  /// Returns true if the device is currently in tablet mode.
  ///
  /// On Windows, this checks if the device is in slate/tablet mode.
  /// On other platforms, this will return false.
  static Future<bool> isTabletMode() {
    return _platform.isTabletMode();
  }

  /// Returns true if a physical keyboard is attached to the device.
  ///
  /// This attempts to detect physical keyboards and returns false for
  /// virtual/on-screen keyboards.
  static Future<bool> isKeyboardAttached() {
    return _platform.isKeyboardAttached();
  }

  /// Returns true if the device has touch screen capability.
  static Future<bool> hasTouchScreen() {
    return _platform.hasTouchScreen();
  }

  /// Returns the maximum number of touch points supported by the device.
  static Future<int> getMaximumTouchPoints() {
    return _platform.getMaximumTouchPoints();
  }

  /// Returns true if this is a convertible (2-in-1) device that can switch between tablet and laptop modes.
  ///
  /// This helps distinguish between pure tablets and convertible devices like Surface Pro, Lenovo Yoga, etc.
  static Future<bool> isConvertibleDevice() {
    return _platform.isConvertibleDevice();
  }

  /// Debug function to log raw input devices for diagnostics.
  ///
  /// This outputs detailed information about all input devices detected by Windows,
  /// helping to diagnose keyboard detection issues on specific hardware.
  static Future<String> debugLogInputDevices() {
    return _platform.debugLogInputDevices();
  }

  /// Returns information about attached keyboard devices.
  ///
  /// This method uses proper HID classification to identify keyboard devices:
  /// - Standard keyboards (dwType == RIM_TYPEKEYBOARD)
  /// - HID keyboards (dwType == RIM_TYPEHID with UsagePage: 0x0001, Usage: 0x0006)
  ///
  /// Returns detailed information about all detected keyboard devices.
  static Future<String> getKeyboardDevices() {
    return _platform.getKeyboardDevices();
  }

  /// Returns comprehensive device information including all tablet mode related data.
  ///
  /// The returned map contains:
  /// - 'isTabletMode': bool indicating if device is in tablet mode
  /// - 'isKeyboardAttached': bool indicating if keyboard is attached
  /// - 'hasTouchScreen': bool indicating if device has touch screen
  /// - 'maxTouchPoints': int indicating maximum touch points supported
  static Future<Map<String, dynamic>> getDeviceInfo() {
    return _platform.getDeviceInfo();
  }

  /// Sets a mock platform implementation for testing.
  ///
  @visibleForTesting
  static set platform(TabletModePlatform platformInstance) {
    _platform = platformInstance;
  }

  /// Returns a stream that emits true when tablet mode is active, false when inactive.
  /// Returns null on platforms that don't support listening for changes.
  static Stream<bool>? get tabletModeChanges {
    return _platform.tabletModeChanges;
  }

  static ValueNotifier<bool> createTabletModeNotifier() {
    // if (kDebugMode) {
    //   debugPrint('Creating tablet mode notifier...');
    // }

    final notifier = ValueNotifier<bool>(false);

    // Set initial value
    isTabletMode().then((value) {
      // if (kDebugMode) {
      //   debugPrint('Initial tablet mode set to: $value');
      // }
      notifier.value = value;
    });

    // Listen for changes and update the notifier
    tabletModeChanges?.listen(
      (isTablet) {
        // if (kDebugMode) {
        //   debugPrint('Tablet mode stream received update: $isTablet');
        // }
        notifier.value = isTablet;
      },
      onError: (error) {
        // if (kDebugMode) {
        //   debugPrint('Tablet mode notifier error: $error');
        // }
      },
      onDone: () {
        // if (kDebugMode) {
        //   debugPrint('Tablet mode stream completed');
        // }
      },
    );

    // if (kDebugMode) {
    //   debugPrint('Tablet mode notifier created and listening for changes');
    // }

    return notifier;
  }

  /// Manually triggers a tablet mode detection and notification for testing
  /// This is useful for debugging when automatic detection isn't working
  static Future<void> testTabletModeDetection() async {
    try {
      // Get current tablet mode
      final isTablet = await isTabletMode();
      if (kDebugMode) debugPrint('isTablet: $isTablet');

      // Manually trigger the stream update
      tabletModeChanges
          ?.listen((mode) {})
          .cancel(); // Cancel immediately after testing
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'Manual tablet mode test failed',
        context: {
          'class': 'TabletModeDetector',
          'method': 'testTabletModeDetection'
        },
      );
    }
  }
}

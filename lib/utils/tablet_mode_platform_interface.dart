/// Platform interface for tablet mode detection.
///
/// This defines the contract that platform-specific implementations must satisfy.
abstract class TabletModePlatform {
  /// Returns true if the device is currently in tablet mode.
  Future<bool> isTabletMode();

  /// Returns true if a physical keyboard is attached to the device.
  Future<bool> isKeyboardAttached();

  /// Returns true if the device has touch screen capability.
  Future<bool> hasTouchScreen();

  /// Returns the maximum number of touch points supported by the device.
  Future<int> getMaximumTouchPoints();

  /// Returns true if this is a convertible (2-in-1) device that can switch between tablet and laptop modes.
  Future<bool> isConvertibleDevice();

  /// Debug function to log raw input devices for diagnostics
  Future<String> debugLogInputDevices();

  /// Returns information about attached keyboard devices
  Future<String> getKeyboardDevices();

  /// Returns comprehensive device information including all tablet mode related data.
  Future<Map<String, dynamic>> getDeviceInfo();

  /// Stream that emits tablet mode changes (true = tablet mode, false = laptop mode).
  /// Returns null on platforms that don't support listening for changes.
  Stream<bool>? get tabletModeChanges;
}

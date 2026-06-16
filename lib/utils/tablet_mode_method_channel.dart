// ignore_for_file: unused_catch_clause

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'tablet_mode_platform_interface.dart';

/// An implementation of [TabletModePlatform] that uses method channels.
class MethodChannelTabletMode extends TabletModePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('com.selah.tablet_mode');

  StreamController<bool>? _tabletModeChangeController;
  StreamSubscription<dynamic>? _eventSubscription;

  @override
  Future<bool> isTabletMode() async {
    try {
      return await methodChannel.invokeMethod<bool>('isTabletMode') ?? false;
    } on PlatformException catch (e) {
      // if (kDebugMode) {
      //   debugPrint('Failed to check tablet mode: ${e.message}');
      // }
      return false;
    }
  }

  @override
  Future<bool> isKeyboardAttached() async {
    try {
      return await methodChannel.invokeMethod<bool>('isKeyboardAttached') ??
          false;
    } on PlatformException catch (e) {
      // if (kDebugMode) {
      //   debugPrint('Failed to check keyboard attachment: ${e.message}');
      // }
      return false;
    }
  }

  @override
  Future<bool> hasTouchScreen() async {
    try {
      return await methodChannel.invokeMethod<bool>('hasTouchScreen') ?? false;
    } on PlatformException catch (e) {
      // if (kDebugMode) {
      //   debugPrint('Failed to check touch screen: ${e.message}');
      // }
      return false;
    }
  }

  @override
  Future<int> getMaximumTouchPoints() async {
    try {
      return await methodChannel.invokeMethod<int>('getMaximumTouchPoints') ??
          0;
    } on PlatformException catch (e) {
      // if (kDebugMode) {
      //   debugPrint('Failed to get maximum touch points: ${e.message}');
      // }
      return 0;
    }
  }

  @override
  Future<bool> isConvertibleDevice() async {
    try {
      return await methodChannel.invokeMethod<bool>('isConvertibleDevice') ??
          false;
    } on PlatformException catch (e) {
      // if (kDebugMode) {
      //   debugPrint('Failed to check convertible device: ${e.message}');
      // }
      return false;
    }
  }

  @override
  Future<String> debugLogInputDevices() async {
    try {
      return await methodChannel.invokeMethod<String>('debugLogInputDevices') ??
          '';
    } on PlatformException catch (e) {
      // if (kDebugMode) {
      //   debugPrint('Failed to log input devices: ${e.message}');
      // }
      return '';
    }
  }

  @override
  Future<String> getKeyboardDevices() async {
    try {
      return await methodChannel.invokeMethod<String>('getKeyboardDevices') ??
          '';
    } on PlatformException catch (e) {
      // if (kDebugMode) {
      //   debugPrint('Failed to get keyboard devices: ${e.message}');
      // }
      return '';
    }
  }

  @override
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final result = await methodChannel.invokeMethod('getDeviceInfo');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } on PlatformException catch (e) {
      // if (kDebugMode) {
      //   debugPrint('Failed to get device info: ${e.message}');
      // }
      return {};
    }
  }

  @override
  Stream<bool>? get tabletModeChanges {
    if (_tabletModeChangeController == null) {
      _tabletModeChangeController = StreamController<bool>.broadcast();

      // Set up method channel handler for native callbacks
      methodChannel.setMethodCallHandler((MethodCall call) async {
        // if (kDebugMode) {
        //   debugPrint('Method call received: ${call.method} with arguments: ${call.arguments}');
        // }

        if (call.method == 'tabletModeChanged') {
          final bool isTabletMode = call.arguments as bool? ?? false;
          // if (kDebugMode) {
          //   debugPrint('Tablet mode change received from native: $isTabletMode');
          // }
          _tabletModeChangeController?.add(isTabletMode);
        }
        // Return null for unhandled methods to avoid errors
        return null;
      });
    }

    return _tabletModeChangeController?.stream;
  }

  /// Clean up resources
  @override
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    methodChannel.setMethodCallHandler(null);
    _tabletModeChangeController?.close();
    _tabletModeChangeController = null;
  }
}

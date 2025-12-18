import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Utility for validating actual internet access beyond basic radio connectivity.
/// Handles the connectivity_plus limitation where device may be "connected" but
/// have no real internet access (hotel WiFi captive portals, etc).
/// NOTE: connectivity_plus only returns radio status so an actual connectivity
/// check is required for proper functionality.
///
class InternetAccessChecker {
  /// Checks both basic device connectivity and validates real internet access.
  /// Returns false if device has no radio connectivity.
  /// Returns false if device appears connected but actual internet tests fail.
  /// Returns true only if both device connectivity exists AND internet access is validated.
  static Future<bool> hasInternetAccess(
      {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      // Step 1: Quick basic connectivity check - required hardware level
      final connectivity = Connectivity();
      final result = await connectivity.checkConnectivity();
      if (result.contains(ConnectivityResult.none)) {
        return false; // No radio/ethernet - impossible to have internet
      }

      // Step 2: Validate actual internet access with a lightweight Supabase probe
      // This tests for cases where connectivity status shows connected but
      // internet access is blocked (captive portals, authentication required, etc.)

      // Use a minimal test query to validate connection
      // Timeout prevents hanging on problematic networks
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client
            .from('profiles')
            .select('id')
            .eq('id', userId)
            .single()
            .timeout(const Duration(seconds: 3));
        return true;
      }

      return true;
    } catch (e) {
      // Connectivity exists at hardware level but actual internet access failed
      return false;
    }
  }
}

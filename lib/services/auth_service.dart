import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_sync_service.dart';
import '../utils/internet_access_checker.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Handle Supabase Auth errors with specific messages
  Exception _handleAuthError(dynamic error) {
    if (error is AuthException) {
      switch (error.message) {
        case 'User already registered':
          return Exception(
              'An account with this email already exists. Please sign in instead.');
        case 'Invalid login credentials':
          return Exception(
              'Invalid username or password. Please check your credentials.');
        case 'Email not confirmed':
          return Exception(
              'Please check your email and confirm your account before signing in.');
        case 'Too many requests':
          return Exception('Too many failed attempts. Please try again later.');
        case 'Signup is disabled':
          return Exception('New account registration is currently disabled.');
        default:
          return Exception('An authentication error occurred: ${error.message}');
      }
    } else {
      return Exception('$error');
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      await SupabaseSyncService().prepareForSignOut();
      await _supabase.auth.signOut();
    } catch (e) {
      throw Exception('Sign out failed: $e');
    }
  }

  // Username/Password Sign Up
  Future<User?> signUpWithUsername(String username, String password) async {
    try {
      // Check if username already exists using RPC to bypass RLS
      try {
        final response = await _supabase.rpc('get_user_email_by_username',
            params: {'username_param': username}).single();
        if (response['email'] != null) {
          throw Exception(
              'That username is already taken. Please choose a different one.');
        }
      } catch (e) {
        // If RPC fails or no user found, continue with signup
        if (kDebugMode) debugPrint('Username check: $e');
      }

      // Generate unique email
      const uuid = Uuid();
      final generatedEmail = '$username-${uuid.v4()}@selah.app';

      // Create user with Supabase Auth
      final response = await _supabase.auth.signUp(
        email: generatedEmail,
        password: password,
      );

      // Store username in profiles table
      await _supabase.from('profiles').insert({
        'id': response.user!.id,
        'username': username,
      });

      return response.user;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  // Username/Password Sign In
  Future<User?> signInWithUsername(String username, String password) async {
    try {
      if (kDebugMode) debugPrint('=== DEBUG signInWithUsername ===');
      if (kDebugMode) debugPrint('Attempting to sign in with username: $username');

      // Check network connectivity before attempting authentication
      final hasInternet = await InternetAccessChecker.hasInternetAccess();
      if (!hasInternet) {
        throw Exception(
            'No internet connection. Please check your network settings and try again.');
      }

      // Get the email associated with the username
      final userData = await _getUserByUsername(username);
      if (kDebugMode) {
        debugPrint('userData from _getUserByUsername: ${userData?.toString()}');
      }

      if (userData == null) {
        if (kDebugMode) debugPrint('No user data found for username: $username');
        throw Exception(
            'No account found with this username. If you want this username please sign up first.');
      }

      final email = userData['email'];
      if (kDebugMode) debugPrint('Found email for username: $email');

      // Sign in with the email and password
      if (kDebugMode) {
        debugPrint('Attempting Supabase signInWithPassword with email: $email');
      }
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (kDebugMode) {
        debugPrint('Sign in successful! User: ${response.user?.toString()}');
      }
      return response.user;
    } catch (e) {
      if (kDebugMode) debugPrint('ERROR in signInWithUsername: $e');
      throw _handleAuthError(e);
    }
  }

  // Helper method to get user email by username using RPC to bypass RLS
  Future<Map<String, dynamic>?> _getUserByUsername(String username) async {
    try {
      if (kDebugMode) debugPrint('=== DEBUG _getUserByUsername ===');
      if (kDebugMode) debugPrint('Looking up username: $username');

      // Use RPC function to get email by username (bypasses RLS)
      if (kDebugMode) debugPrint('Calling RPC function get_user_email_by_username');
      final response = await _supabase.rpc('get_user_email_by_username',
          params: {'username_param': username}).single();
      if (kDebugMode) debugPrint('RPC response: ${response.toString()}');

      if (response['email'] == null) {
        if (kDebugMode) debugPrint('No email found for username: $username');
        return null;
      }

      return {
        'username': username,
        'email': response['email'],
      };
    } catch (e) {
      if (kDebugMode) debugPrint('ERROR in _getUserByUsername: $e');
      if (kDebugMode) debugPrint('Stack trace: ${e.toString()}');

      // Enhanced error handling for network issues
      if (e.toString().contains('NetworkError') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Connection failed')) {
        throw Exception(
            'Network connection error. Please check your internet connection and try again.');
      }

      return null;
    }
  }

  // Change password - Supabase approach
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No user is currently signed in');
    }

    try {
      // Supabase doesn't have a direct password change with current password verification
      // We need to use the updateUser method which requires the user to be recently authenticated
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } catch (e) {
      if (e is AuthException) {
        switch (e.message) {
          case 'Password should be at least 6 characters':
            throw Exception(
                'The new password is too weak. Please choose a stronger password.');
          case 'session_not_found':
          case 'refresh_token_not_found':
            throw Exception(
                'Your session has expired. Please sign out and sign back in before changing your password.');
          default:
            throw Exception(
                'Password change failed. Please sign out and sign back in to try again.');
        }
      }
      throw Exception('Password change failed: $e');
    }
  }

  // Delete account
  // Replace the deleteAccount method with this:
  Future<void> deleteAccount(String password) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No user is currently signed in');
    }

    try {
      // Delete all synced user data from Supabase tables (uses anon key - safe)
      final syncService = SupabaseSyncService();
      await syncService.deleteAllRemoteHighlights();
      await syncService.deleteAllRemoteNotes();
      await syncService.deleteAllRemoteHistory();
      await syncService.deleteAllRemoteSearchHistory();

      // Call Edge Function to delete the auth user (secure - uses service role on server)
      final response = await _supabase.functions
          .invoke('delete-user-account', body: {'userId': user.id});

      // Check if Edge Function call succeeded
      if (response.data == null || response.data['success'] != true) {
        throw Exception('Failed to delete user account');
      }

      // ✅ NEW: Cleanup sync service and sign out
      await syncService.prepareForSignOut();
      await _supabase.auth.signOut();

      // ✅ NEW: Clear all sync timestamps from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('lastHighlightsSync');
      await prefs.remove('lastNotesSync');
      await prefs.remove('lastHistorySync');
      await prefs.remove('lastSearchHistorySync');
      await prefs.remove('pendingHighlightsQueue');
      await prefs.remove('pendingNotesQueue');
      await prefs.remove('pendingHistoryQueue');
      await prefs.remove('pendingSearchHistoryQueue');
    } catch (e) {
      if (kDebugMode) debugPrint('Account deletion failed: $e');
      throw Exception('Account deletion failed: $e');
    }
  }

  // Get cached username (for main.dart display)
  static Future<String?> getCachedUsername() async {
    return await SupabaseSyncService.getCachedUsername();
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_sync_service.dart';
import '../utils/internet_access_checker.dart';
import '../utils/error_handler.dart';

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
          return Exception(
              'An authentication error occurred: ${error.message}');
      }
    } else {
      return Exception('$error');
    }
  }

  // Sign Out
  Future<void> signOut({bool preservePendingOperations = true}) async {
    try {
      await SupabaseSyncService().prepareForSignOut(
          preservePendingOperations: preservePendingOperations);
      await _supabase.auth.signOut();
    } catch (e) {
      throw Exception('Sign out failed: ${e.toString()}');
    }
  }

  // Username/Password Sign Up
  Future<User?> signUpWithUsername(String username, String password) async {
    try {
      // Check if username already exists using RPC to bypass RLS
      // This requires the database function created using supabase/get_user_email_by_username.sql
      try {
        final response = await _supabase.rpc('get_user_email_by_username',
            params: {'username_param': username}).single();
        if (response['email'] != null) {
          throw Exception(
              'That username is already taken. Please choose a different one.');
        }
      } catch (e) {
        // If RPC fails or no user found, continue with signup
        ErrorHandler.logError(
          e,
          customMessage: 'RPC get_user_email_by_username lookup failed',
          context: {
            'class': 'AuthService',
            'method': 'signUpWithUsername',
            'username': username
          },
        );
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
      // Check network connectivity before attempting authentication
      final hasInternet = await InternetAccessChecker.hasInternetAccess();
      if (!hasInternet) {
        throw Exception(
            'No internet connection. Please check your network settings and try again.');
      }

      // Get the email associated with the username
      final userData = await _getUserByUsername(username);

      if (userData == null) {
        ErrorHandler.logError(
          'No user data found for username: $username',
          context: {
            'class': 'AuthService',
            'method': 'signInWithUsername',
            'username': username
          },
        );
        throw Exception('No account found with this username.');
      }

      final email = userData['email'];

      // Sign in with the email and password
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      return response.user;
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'SignInWithUsername exception',
        context: {
          'class': 'AuthService',
          'method': 'signInWithUsername',
          'error': e.toString()
        },
      );
      throw _handleAuthError(e);
    }
  }

  // Helper method to get user email by username using RPC to bypass RLS
  Future<Map<String, dynamic>?> _getUserByUsername(String username) async {
    try {
      // Use RPC function to get email by username (bypasses RLS)
      final response = await _supabase.rpc('get_user_email_by_username',
          params: {'username_param': username}).single();

      if (response['email'] == null) {
        ErrorHandler.logError(
          null,
          customMessage: 'No email found for username',
          context: {
            'class': 'AuthService',
            'method': '_getUserByUsername',
            'username': username
          },
        );
        return null;
      }

      return {
        'username': username,
        'email': response['email'],
      };
    } catch (e) {
      ErrorHandler.logError(
        e,
        context: {
          'class': 'AuthService',
          'method': '_getUserByUsername',
          'username': username,
          'error': e.toString(),
        },
      );

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
  Future<void> changePassword(
      String currentPassword, String newPassword) async {
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
      throw Exception('Password change failed: ${e.toString()}');
    }
  }

  // Delete account
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
      await syncService.prepareForSignOut(preservePendingOperations: false);
      await _supabase.auth.signOut();

      // ✅ NEW: Clear all sync timestamps from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('lastHighlightsSync');
      await prefs.remove('lastNotesSync');
      await prefs.remove('lastHistorySync');
      await prefs.remove('lastSearchHistorySync');
      // These should only be cleared if the user chooses to do so,
      // which they currently cannot do except by manually editing
      // the shared preferences. If they are online these should have
      // been processed already otherwise we have a bigger problem.
      //
      // await prefs.remove('pendingHighlightsQueue');
      // await prefs.remove('pendingNotesQueue');
      // await prefs.remove('pendingHistoryQueue');
      // await prefs.remove('pendingSearchHistoryQueue');
    } catch (e) {
      ErrorHandler.logError(
        'Account deletion failed: ${e.toString()}',
        context: {
          'class': 'AuthService',
          'method': 'deleteAccount',
          'error': e.toString()
        },
      );
      throw Exception('Account deletion failed: ${e.toString()}');
    }
  }

  // Get cached username (for main.dart display)
  // static Future<String?> getCachedUsername() async {
  //   return await SupabaseSyncService.getCachedUsername();
  // }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selah/utils/internet_access_checker.dart';
import 'package:uuid/uuid.dart';
import 'firestore_sync_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Handle Firebase Auth errors with specific messages
  Exception _handleAuthError(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return Exception('An account with this email already exists. Please sign in instead.');
        case 'weak-password':
          return Exception('Password is too weak. Please choose a stronger password.');
        case 'invalid-email':
          return Exception('That username is invalid.');
        case 'user-disabled':
          return Exception('This account has been disabled. Please contact support.');
        case 'user-not-found':
          return Exception('No account found with this email. Please sign up first.');
        case 'wrong-password':
          return Exception('Incorrect password. Please try again.');
        case 'too-many-requests':
          return Exception('Too many failed attempts. Please try again later.');
        case 'operation-not-allowed':
          return Exception('Email/password authentication is not enabled. Please check Firebase console settings.');
        case 'network-request-failed':
          return Exception('Network error. Please check your internet connection and try again.');
        case 'invalid-credential':
          return Exception('Invalid username or password. Please check your credentials.');
        case 'account-exists-with-different-credential':
          return Exception('An account already exists with this email using a different sign-in method.');
        case 'invalid-verification-code':
          return Exception('Invalid verification code. Please try again.');
        case 'invalid-verification-id':
          return Exception('Invalid verification ID. Please try again.');
        case 'captcha-check-failed':
          return Exception('Captcha verification failed. Please try again.');
        case 'app-deleted':
          return Exception('The Firebase app has been deleted. Please contact support.');
        case 'app-not-authorized':
          return Exception('App is not authorized to use Firebase Authentication.');
        case 'argument-error':
          return Exception('Invalid argument provided to authentication method.');
        case 'invalid-api-key':
          return Exception('Invalid API key. Please check your Firebase configuration.');
        case 'invalid-user-token':
          return Exception('Invalid user token. Please sign in again.');
        case 'web-storage-unsupported':
          return Exception('Web storage is not supported in this browser.');
        case 'invalid-continue-uri':
          return Exception('Invalid continue URL provided.');
        case 'missing-continue-uri':
          return Exception('Missing continue URL.');
        case 'unauthorized-continue-uri':
          return Exception('Unauthorized continue URL.');
        case 'missing-verification-code':
          return Exception('Missing verification code.');
        case 'missing-verification-id':
          return Exception('Missing verification ID.');
        case 'missing-phone-number':
          return Exception('Missing phone number.');
        case 'invalid-phone-number':
          return Exception('Invalid phone number format.');
        case 'missing-email':
          return Exception('Missing email address.');
        case 'session-cookie-expired':
          return Exception('Session has expired. Please sign in again.');
        case 'session-cookie-revoked':
          return Exception('Session has been revoked. Please sign in again.');
        case 'uid-already-exists':
          return Exception('A user with this UID already exists.');
        case 'sign-in-failed':
          return Exception('Sign in failed. Please try again.');
        case 'web-context-already-presented':
          return Exception('Web context already presented.');
        case 'web-context-cancelled':
          return Exception('Web context cancelled.');
        case 'quota-exceeded':
          return Exception('Service quota exceeded. Please try again later.');
        case 'retry-phone-auth':
          return Exception('Phone authentication failed. Please try again.');
        case 'provider-already-linked':
          return Exception('Provider already linked to this account.');
        case 'requires-recent-login':
          return Exception('This operation requires recent authentication. Please sign in again.');
        case 'credential-already-in-use':
          return Exception('This credential is already associated with another account.');
        case 'email-change-needs-verification':
          return Exception('Email change requires verification.');
        case 'no-current-user':
          return Exception('No user is currently signed in.');
        case 'no-auth-event':
          return Exception('No authentication event found.');
        case 'no-internet':
          return Exception('No internet connection. Please check your network and try again.');
        case 'unknown':
        default:
          return Exception('An unknown login error occured. Please double check your username and password and try again.');
      }
    } else {
      return Exception('$error');
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      await FirestoreSyncService().prepareForSignOut();
      await _auth.signOut();
    } catch (e) {
      throw Exception('Sign out failed: $e');
    }
  }

  // Username/Password Sign Up
  Future<User?> signUpWithUsername(String username, String password) async {
    try {
      // Check if username already exists
      final existingUser = await _getUserByUsername(username);
      if (existingUser != null) {
        throw Exception('That username is already taken. Please choose a different one.');
      }

      // Generate unique email
      const uuid = Uuid();
      final generatedEmail = '$username-${uuid.v4()}@selah.app';

      // Create user with Firebase Auth
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: generatedEmail,
        password: password,
      );

      // Store username and email in Firestore
      await FirebaseFirestore.instance.collection('users').doc(result.user!.uid).set({
        'username': username,
        'email': generatedEmail,
        'created_at': FieldValue.serverTimestamp(),
      });

      return result.user;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  // Username/Password Sign In
  Future<User?> signInWithUsername(String username, String password) async {
    try {
      // Get the email associated with the username

      final userData = await _getUserByUsername(username);
      if (userData == null) {
        throw Exception('No account found with this username. If you want this username please sign up beforing logging in.');
      }

      final email = userData['email'];

      // Sign in with the email and password

      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return result.user;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  // Helper method to get user data by username
  Future<Map<String, dynamic>?> _getUserByUsername(String username) async {
    try {
      final querySnapshot =
          await FirebaseFirestore.instance.collection('users').where('username', isEqualTo: username).limit(1).get();

      if (querySnapshot.docs.isNotEmpty) {
        final userData = querySnapshot.docs.first.data();

        return userData;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Helper method to get user data by user ID (for signed-in users)
  Future<Map<String, dynamic>?> _getCurrentUserData() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      return null;
    }
  }

  // Change password - direct approach: requires current password for immediate reauthentication
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No user is currently signed in');
    }

    // Store the user's Firestore data for automated reauth
    final userData = await _getCurrentUserData();
    final username = userData?['username'] as String?;

    try {
      // First, reload user state to ensure we have fresh authentication data

      await user.reload();
      final reloadedUser = _auth.currentUser;

      if (reloadedUser == null) {
        throw Exception('Authentication state lost. Please sign back in.');
      }

      // Get the user's hidden email from Firestore (required for username-based auth)
      final email = userData?['email'] as String? ?? user.email;

      if (email == null) {
        throw Exception('Could not retrieve user email for authentication');
      }

      // Create credential with current password - Firebase requires this to prove identity
      AuthCredential currentCredentials;
      try {
        currentCredentials = EmailAuthProvider.credential(
          email: email,
          password: currentPassword,
        );
      } catch (credError) {
        throw Exception('Failed to prepare authentication credentials');
      }

      // Step 1: Reauthenticate with current credentials (proves identity)

      // Add timeout to catch Firebase Auth hanging due to threading issues on Windows
      const timeout = Duration(seconds: 5);
      await user.reauthenticateWithCredential(currentCredentials).timeout(
        timeout,
        onTimeout: () {
          // Force trigger automated reauth by throwing the specific error
          throw FirebaseAuthException(code: 'unknown-error', message: 'Operation timed out due to thread violation');
        },
      );

      // Step 2: Update password (now authorized for sensitive operations)

      await user.updatePassword(newPassword);
    } catch (e) {
      // Handle specific Firebase errors
      if (e is FirebaseAuthException) {
        // Special handling for Windows desktop firebase_auth/unknown-error - attempt automated reauth FIRST
        if (e.code == 'unknown-error') {
          // Attempt automated sign-out/sign-in cycle for desktop platforms
          await _attemptAutomatedReauth(username, currentPassword, newPassword);
          return; // Success - exit method
        }

        // Handle other Firebase error codes (after checking for special automated reauth case)
        switch (e.code) {
          case 'wrong-password':
            throw Exception('The current password you entered is incorrect. Please try again.');
          case 'user-not-found':
            throw Exception('User account not found. Please sign back in.');
          case 'too-many-requests':
            throw Exception('Too many password change attempts. Please wait a moment and try again.');
          case 'weak-password':
            throw Exception('The new password is too weak. Please choose a stronger password.');
          case 'requires-recent-login':
            throw Exception('Your session has expired. Please sign out and sign back in before changing your password.');
          // Removed 'unknown' case from switch - it's handled by automated reauth above
          default:
            throw Exception('An authentication error occurred. Please sign out and sign back in before trying again.');
        }
      }

      // Re-throw other exceptions with generic message
      throw Exception('Password change failed. Please sign out and sign back in to try again.');
    }
  }

  // Attempt automated sign-out/sign-in cycle when firebase_auth/unknown-error occurs
  Future<void> _attemptAutomatedReauth(String? username, String currentPassword, String newPassword) async {
    // Step 0: Check device and Firebase connectivity before attempting automated reauth

    // First check device connectivity
    bool hasDeviceConnectivity = await InternetAccessChecker.hasInternetAccess();
    if (!hasDeviceConnectivity) {
      throw Exception('Network error. Please check your internet connection and try again.');
    }

    // Device is online, now check Firebase connectivity

    bool hasFirebaseConnectivity = await FirestoreSyncService().checkFirebaseConnection();
    if (!hasFirebaseConnectivity) {
      throw Exception('Network error. Please check your internet connection and try again.');
    }

    try {
      // Step 1: Sign out the user

      await _auth.signOut();

      // Wait a moment for sign out to complete
      await Future.delayed(const Duration(seconds: 3));

      // Step 2: Sign back in with the provided credentials

      User? newUser;
      if (username != null) {
        // Use username-based sign in
        newUser = await signInWithUsername(username, currentPassword);
      }

      if (newUser == null) {
        throw Exception('Failed to reauthenticate automatically. Please sign in manually and try again.');
      }

      // Step 3: Now retry the password change with fresh authentication
      await _performPasswordChangeWithFreshAuth(newPassword);
    } catch (reauthError) {
      // Automated reauth failed - throw the original error to trigger manual process
      throw Exception('An authentication error occurred. Please sign out and sign back in before trying again.');
    }
  }

  // Attempt automated sign-out/sign-in cycle when firebase_auth/unknown-error occurs during account deletion
  Future<void> _attemptAutomatedDeleteReauth(String? username, String password) async {
    // Step 0: Check device and Firebase connectivity before attempting automated reauth

    // First check device connectivity (no network calls)
    bool hasDeviceConnectivity = await InternetAccessChecker.hasInternetAccess();
    if (!hasDeviceConnectivity) {
      throw Exception('Network error. Please check your internet connection and try again.');
    }

    // Device is online, now check Firebase connectivity
    bool hasFirebaseConnectivity = await FirestoreSyncService().checkFirebaseConnection();
    if (!hasFirebaseConnectivity) {
      throw Exception('Network error. Please check your internet connection and try again.');
    }

    try {
      // Step 1: Sign out the current user

      await _auth.signOut();

      // Wait a moment for sign out to complete
      await Future.delayed(const Duration(seconds: 3));

      // Step 2: Sign back in with fresh authentication
      User? newUser;
      if (username != null) {
        // Use username-based sign in
        newUser = await signInWithUsername(username, password);
      } else {
        throw Exception('Unable to reauthenticate automatically. Please sign in manually.');
      }

      if (newUser == null) {
        throw Exception('Failed to reauthenticate automatically. Please sign in manually and try again.');
      }

      // Step 3: Now retry the full account deletion process with fresh authentication
      await _performAccountDeletionWithFreshAuth(newUser);
    } catch (reauthError) {
      // Automated reauth failed - throw a user-friendly message
      throw Exception(
          'Account deletion encountered an authentication error. Please sign in again and try deleting your account manually.');
    }
  }

  // Perform account deletion after fresh authentication
  Future<void> _performAccountDeletionWithFreshAuth(User user) async {
    // Delete all synced user data from Firestore subcollections BEFORE deleting the account
    final syncService = FirestoreSyncService();
    await syncService.deleteAllRemoteHighlights();
    await syncService.deleteAllRemoteNotes();
    await syncService.deleteAllRemoteHistory();

    // Delete the Firestore user document
    await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();

    // Delete the Firebase Auth account
    await user.delete();
  }

  // Perform password change after fresh authentication
  Future<void> _performPasswordChangeWithFreshAuth(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Lost authentication during automated reauth');
    }

    // Directly update password since we just reauthenticated
    await user.updatePassword(newPassword);
  }

  // Delete account - requires password for reauthentication
  Future<void> deleteAccount(String password) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No user is currently signed in');
    }

    // Store the user's Firestore data for automated reauth
    final userData = await _getCurrentUserData();
    final username = userData?['username'] as String?;

    try {
      if (username == null) {
        throw Exception('Could not retrieve username for authentication');
      }

      // Look up email using username (same pattern as signInWithUsername)

      final querySnapshot =
          await FirebaseFirestore.instance.collection('users').where('username', isEqualTo: username).limit(1).get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('User data not found in database');
      }

      final userDoc = querySnapshot.docs.first;
      final email = userDoc.data()['email'] as String?;

      if (email == null) {
        throw Exception('Could not retrieve user email for authentication');
      }

      // Create credential with username-resolved email + password
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      // Add timeout to catch Firebase Auth hanging due to threading issues on Windows
      const timeout = Duration(seconds: 5);
      await user.reauthenticateWithCredential(credential).timeout(
        timeout,
        onTimeout: () {
          // Force trigger automated reauth by throwing the specific error
          throw FirebaseAuthException(code: 'unknown-error', message: 'Operation timed out due to thread violation');
        },
      );

      // Delete all synced user data from Firestore subcollections BEFORE deleting the account
      final syncService = FirestoreSyncService();
      await syncService.deleteAllRemoteHighlights();
      await syncService.deleteAllRemoteNotes();
      await syncService.deleteAllRemoteHistory();

      // Delete the Firestore user document
      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();

      // Delete the Firebase Auth account with timeout as well
      await user.delete().timeout(
        timeout,
        onTimeout: () {
          // Force trigger automated reauth by throwing the specific error
          throw FirebaseAuthException(code: 'unknown-error', message: 'Delete operation timed out due to thread violation');
        },
      );
    } catch (e) {
      // Handle specific Firebase errors
      if (e is FirebaseAuthException) {
        // Special handling for Windows desktop firebase_auth/unknown-error - attempt automated reauth FIRST
        if (e.code == 'unknown-error') {
          // Attempt automated sign-out/sign-in cycle for desktop platforms
          await _attemptAutomatedDeleteReauth(username, password);
          return; // Success - exit method
        }

        // Handle other Firebase error codes
        switch (e.code) {
          case 'wrong-password':
            throw Exception('The password you entered is incorrect. Please try again.');
          case 'user-not-found':
            throw Exception('User account not found. Please sign back in.');
          case 'too-many-requests':
            throw Exception('Too many deletion attempts. Please wait a moment and try again.');
          case 'requires-recent-login':
            throw Exception(
                'This operation requires recent authentication. Please sign out and sign back in before deleting your account.');
          default:
            throw Exception('An authentication error occurred. Please sign out and sign back in before trying again.');
        }
      }

      // Re-throw other exceptions with generic message
      throw Exception('Account deletion failed. Please sign out and sign back in to try again.');
    }
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../main.dart';
import '../utils/preferences_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../utils/error_handler.dart';
import '../services/supabase_sync_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  //final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _signInButtonFocusNode = FocusNode();

  bool _isSignUp = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    //WidgetsBinding.instance.addPostFrameCallback((_) {
    //  _usernameFocusNode.requestFocus();
    //});
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    //_usernameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all fields';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      User? user;
      if (_isSignUp) {
        user = await _authService.signUpWithUsername(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        user = await _authService.signInWithUsername(
          _emailController.text.trim(),
          _passwordController.text,
        );
      }

      if (user != null && mounted) {
        // Show sync options dialog after successful authentication
        await _showSyncDialog();

        // Show sync progress dialog during initialization
        // if (mounted) {
        //   showDialog(
        //     context: context,
        //     barrierDismissible: false,
        //     builder: (context) => AlertDialog(
        //       content: Column(
        //         mainAxisSize: MainAxisSize.min,
        //         children: [
        //           CircularProgressIndicator(),
        //           const SizedBox(height: 16),
        //           Text('Initializing sync service...', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
        //         ],
        //       ),
        //     ),
        //   );
        // }

        // Initialize sync service AFTER user has confirmed preferences
        //if (mounted) {
        // Show sync progress dialog during initialization
        //   showDialog(
        //     context: context,
        //     barrierDismissible: false,
        //     builder: (context) => AlertDialog(
        //       content: Column(
        //         mainAxisSize: MainAxisSize.min,
        //         children: [
        //           CircularProgressIndicator(),
        //           const SizedBox(height: 16),
        //           Text('Initializing sync service...', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
        //         ],
        //       ),
        //     ),
        //   );
        // }

        try {
          ErrorHandler.logError('About to initialize SupabaseSyncService after user confirmed preferences...');

          final syncService = SupabaseSyncService();
          await syncService.initialize(isLoginResync: true);

          ErrorHandler.logError('SyncService.initialize() completed successfully');
        } catch (e) {
          ErrorHandler.logError(e, customMessage: 'SyncService.initialize() FAILED');
          // Continue even if sync fails - user can still use the app
        }

        // Dismiss sync progress dialog and navigate back
        if (mounted) {
          Navigator.of(context).pop(); // Dismiss sync dialog
          Navigator.of(context).pop(); // Back to main screen
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _errorMessage = _errorMessage?.trim();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool> _showSyncDialog() async {
    // Reload current sync preferences to ensure dialog shows user's actual settings
    await _loadSyncPreferences();
    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 400),
          //title: Text('Sync Data Options', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Choose which categories of data that you want to sync. You can change these settings later in the main options drawer.',
                  style:
                      TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context)),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<bool>(
                  valueListenable: syncHighlightsNotifier,
                  builder: (context, value, child) => SwitchListTile(
                    title: Text('Highlights',
                        style: TextStyle(
                            fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                    value: value,
                    onChanged: (val) {
                      syncHighlightsNotifier.value = val;
                    },
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: syncNotesNotifier,
                  builder: (context, value, child) => SwitchListTile(
                    title: Text('Notes',
                        style: TextStyle(
                            fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                    value: value,
                    onChanged: (val) {
                      syncNotesNotifier.value = val;
                    },
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: syncHistoryNotifier,
                  builder: (context, value, child) => SwitchListTile(
                    title: Text('Verse History',
                        style: TextStyle(
                            fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                    value: value,
                    onChanged: (val) {
                      syncHistoryNotifier.value = val;
                    },
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: syncSearchHistoryNotifier,
                  builder: (context, value, child) => SwitchListTile(
                    title: Text('Search History',
                        style: TextStyle(
                            fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
                    value: value,
                    onChanged: (val) {
                      syncSearchHistoryNotifier.value = val;
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text('Continue',
                  style:
                      TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
              onPressed: () async {
                // Check if all syncs are disabled using shared method
                final atLeastOneEnabled = await checkAtLeastOneSyncEnabled();
                if (!atLeastOneEnabled) {
                  // Show warning using shared method
                  final proceed = await showNoSyncWarningDialog();
                  if (!proceed) return;
                }

                // Save preferences
                await _saveAllCurrentPrefs();

                if (context.mounted) Navigator.pop(context, true);
              },
            ),
          ],
        ),
      );
    }
    return true;
  }

  Future<void> _saveAllCurrentPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Save individual preference keys
    /*
    await prefs.setInt(
        'themeMode', themeModeNotifier.value == ThemeMode.light ? 1 : (themeModeNotifier.value == ThemeMode.dark ? 2 : 0));
    await prefs.setDouble('fontSize', fontSizeNotifier.value);
    await prefs.setString('fontFamily', fontFamilyNotifier.value);
    await prefs.setString('lightPrimaryColor', _colorToHex(lightPrimaryColor.value));
    await prefs.setString('lightBackgroundColor', _colorToHex(lightBackgroundColor.value));
    await prefs.setString('lightTextColor', _colorToHex(lightTextColor.value));
    await prefs.setString('darkPrimaryColor', _colorToHex(darkPrimaryColor.value));
    await prefs.setString('darkBackgroundColor', _colorToHex(darkBackgroundColor.value));
    await prefs.setString('darkTextColor', _colorToHex(darkTextColor.value));
    await prefs.setString('lightHighlightColor', _colorToHex(lightHighlightColor.value));
    await prefs.setString('darkHighlightColor', _colorToHex(darkHighlightColor.value));
    await prefs.setBool('fullscreen', fullscreenNotifier.value);
    await prefs.setBool('showNotesInline', showNotesInlineNotifier.value);
    await prefs.setInt('maxVerticalScreens', maxVerticalScreens.value);
    await prefs.setInt('maxHorizontalScreens', maxHorizontalScreens.value);
    await prefs.setStringList('highlightColors', highlightColorsNotifier.value.map((c) => c.toARGB32().toString()).toList());
    */

    await prefs.setBool('syncHighlights', syncHighlightsNotifier.value);
    await prefs.setBool('syncNotes', syncNotesNotifier.value);
    await prefs.setBool('syncHistory', syncHistoryNotifier.value);
    await prefs.setBool('syncSearchHistory', syncSearchHistoryNotifier.value);
  }

  //String _colorToHex(Color c) => '#${(c.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  // Load current sync preferences before showing the dialog
  Future<void> _loadSyncPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    syncHighlightsNotifier.value = prefs.getBool('syncHighlights') ?? defaultSyncHighlights;
    syncNotesNotifier.value = prefs.getBool('syncNotes') ?? defaultSyncNotes;
    syncHistoryNotifier.value = prefs.getBool('syncHistory') ?? defaultSyncHistory;
    syncSearchHistoryNotifier.value = prefs.getBool('syncSearchHistory') ?? defaultSyncSearchHistory;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(
          size: 32,
          color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
        ),
        title: Text(_isSignUp ? 'Sign up' : 'Sign in',
            style: TextStyle(fontSize: uiFontSize + 4, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            semanticLabel: 'Go back to Bible screen',
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    _isSignUp ? 'Create an account' : 'Sign in to sync your data',
                    style: TextStyle(
                        fontSize: uiFontSize + 8,
                        fontFamily: uiFontFamily,
                        fontWeight: FontWeight.bold,
                        color: getAdaptiveTextColor(context)),
                  ),
                  const SizedBox(height: 16),
                  Center(
                      child: Image.asset(
                    'assets/icon.png',
                    scale: 2.0,
                    isAntiAlias: true,
                    filterQuality: FilterQuality.high,
                  )),
                  const SizedBox(height: 16),
                  TextField(
                    autofocus: true,
                    maxLength: 100,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    controller: _emailController,
                    //focusNode: _usernameFocusNode,
                    decoration: InputDecoration(
                      counter: SizedBox.shrink(), // Hide the counter eg. 0/100
                      labelText: 'Username',
                      labelStyle: TextStyle(
                          fontSize: uiFontSize + 2, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context)),
                      border: OutlineInputBorder(),
                      errorText:
                          _errorMessage?.contains('username') == true || _errorMessage?.contains('Username') == true
                              ? _errorMessage
                              : null,
                    ),
                    keyboardType: TextInputType.text,
                    onSubmitted: (_) => _authenticate(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    maxLength: 100,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    controller: _passwordController,
                    decoration: InputDecoration(
                      counter: SizedBox.shrink(), // Hide the counter eg. 0/100
                      labelText: 'Password',
                      labelStyle: TextStyle(
                          fontSize: uiFontSize + 2, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context)),
                      border: OutlineInputBorder(),
                      errorText: _errorMessage?.contains('password') == true ? _errorMessage : null,
                    ),
                    obscureText: true,
                    onSubmitted: (_) => _authenticate(),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null &&
                      !_errorMessage!.contains('username') &&
                      !_errorMessage!.contains('password'))
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red, fontSize: uiFontSize + 4, fontFamily: uiFontFamily),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    focusNode: _signInButtonFocusNode,
                    onPressed: () {
                      // ALWAYS shift focus away from text fields immediately
                      // Circumvents a bug on windows desktop touchscreens
                      // where the TextField retains focus and the OSK keeps popping
                      // up for events that it shouldn't
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          if (_signInButtonFocusNode.canRequestFocus) {
                            _signInButtonFocusNode.requestFocus();
                          }
                        }
                      });

                      // Only proceed with authentication if not loading
                      if (!_isLoading) {
                        _authenticate();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size(double.infinity, 50),
                    ),
                    child: _isLoading
                        ? CircularProgressIndicator()
                        : Text(
                            _isSignUp ? 'Sign up' : 'Sign in',
                            style: TextStyle(
                                fontSize: uiFontSize + 2,
                                fontFamily: uiFontFamily,
                                color: getAdaptiveTextColor(context, usePrimaryColor: true)),
                          ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isSignUp = !_isSignUp;
                        _errorMessage = null;
                      });
                    },
                    child: Text(
                      _isSignUp ? 'Already have an account? Sign in' : 'Don\'t have an account? Sign up',
                      style: TextStyle(
                          fontSize: uiFontSize + 6, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

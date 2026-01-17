import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'snackbar_notification.dart';

// Error types for categorization
enum ErrorType { network, database, sync, validation, system, unknown }

// Error severity levels
enum ErrorSeverity {
  low, // Log only, no user notification
  medium, // Log and brief user notification
  high // Log and detailed user notification
}

class AppError {
  final String message;
  final ErrorType type;
  final ErrorSeverity severity;
  final dynamic originalError;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? context;

  AppError({
    required this.message,
    required this.type,
    required this.severity,
    this.originalError,
    this.stackTrace,
    this.context,
  });
}

class ErrorHandler {
  // Singleton instance for consistent error handling
  static final ErrorHandler _instance = ErrorHandler._internal();
  factory ErrorHandler() => _instance;
  ErrorHandler._internal();

  // Global error handler for Flutter framework errors
  static void catchFrameworkErrors() {
    FlutterError.onError = (FlutterErrorDetails details) {
      ErrorHandler.handleError(AppError(
        message: 'Framework error: ${details.exception}',
        type: ErrorType.system,
        severity: ErrorSeverity.high,
        originalError: details.exception,
        stackTrace: details.stack,
        context: {
          'library': details.library,
          'summary': details.summary.toString(),
          'silent': details.silent,
        },
      ));
    };
  }

  // Main error handling method
  static Future<void> handleError(AppError error,
      {BuildContext? context}) async {
    // Always log the error
    _logError(error);

    // Show user notification based on severity
    switch (error.severity) {
      case ErrorSeverity.low:
        // No user notification for low severity
        break;
      case ErrorSeverity.medium:
        if (context != null) {
          showStyledSnackBar(context, error.message, isError: true);
        } else {
          showStyledSnackBarGlobal(error.message, isError: true);
        }
        break;
      case ErrorSeverity.high:
        final userMessage = _formatUserMessage(error);
        if (context != null) {
          showStyledSnackBar(context, userMessage, isError: true);
        } else {
          showStyledSnackBarGlobal(userMessage, isError: true);
        }
        break;
    }
  }

  // Convenience method for dynamic errors
  static Future<void> handle(
    dynamic error, {
    String? customMessage,
    ErrorType type = ErrorType.unknown,
    ErrorSeverity severity = ErrorSeverity.medium,
    Map<String, dynamic>? context,
    BuildContext? buildContext,
  }) async {
    final formattedMessage = customMessage ?? _formatErrorMessage(error);
    await handleError(
        AppError(
          message: formattedMessage,
          type: type,
          severity: severity,
          originalError: error,
          stackTrace: StackTrace.current,
          context: context,
        ),
        context: buildContext);
  }

  // Background error logging without user notification
  static Future<void> logError(
    dynamic error, {
    String? customMessage,
    ErrorType type = ErrorType.unknown,
    Map<String, dynamic>? context,
  }) async {
    final formattedMessage = customMessage ?? _formatErrorMessage(error);
    await handleError(AppError(
      message: formattedMessage,
      type: type,
      severity: ErrorSeverity.low,
      originalError: error,
      stackTrace: StackTrace.current,
      context: context,
    ));
  }

  // Handle network errors specifically
  static Future<void> handleNetworkError(
    dynamic error, {
    Map<String, dynamic>? context,
    BuildContext? buildContext,
  }) async {
    var message = 'Network error occurred';
    var severity = ErrorSeverity.medium;

    if (error is SocketException) {
      message = 'No internet connection';
    } else if (error is HttpException) {
      message = 'Server communication error';
    } else if (error.toString().contains('connection')) {
      message = 'Connection failed';
    }

    await handleError(
        AppError(
          message: message,
          type: ErrorType.network,
          severity: severity,
          originalError: error,
          stackTrace: StackTrace.current,
          context: context,
        ),
        context: buildContext);
  }

  // Handle database errors
  static Future<void> handleDatabaseError(
    dynamic error, {
    Map<String, dynamic>? context,
    BuildContext? buildContext,
  }) async {
    final message = 'Database operation failed';
    await handleError(
        AppError(
          message: message,
          type: ErrorType.database,
          severity: ErrorSeverity.high,
          originalError: error,
          stackTrace: StackTrace.current,
          context: context,
        ),
        context: buildContext);
  }

  // Handle sync errors
  static Future<void> handleSyncError(
    dynamic error, {
    Map<String, dynamic>? context,
    BuildContext? buildContext,
  }) async {
    // Build more descriptive message based on context
    String message = 'Sync operation failed';
    ErrorSeverity severity = ErrorSeverity.medium;

    // Enhanced error message with detailed context
    final errorDetails = _buildSyncErrorDetails(error, context);
    message = errorDetails['message'];
    severity = errorDetails['severity'];

    await handleError(
        AppError(
          message: message,
          type: ErrorType.sync,
          severity: severity,
          originalError: error,
          stackTrace: StackTrace.current,
          context: context,
        ),
        context: buildContext);
  }

  // Build detailed sync error message with context
  static Map<String, dynamic> _buildSyncErrorDetails(
      dynamic error, Map<String, dynamic>? context) {
    String message = 'Sync operation failed';
    ErrorSeverity severity = ErrorSeverity.medium;

    try {
      // Check if this is a realtime subscription error (less critical)
      if (context != null && context.containsKey('table')) {
        final tableName = context['table'];
        message =
            'Realtime sync for $tableName encountered an issue (sync will continue)';
        severity = ErrorSeverity.low; // Realtime errors are less critical

        // Add specific error details if available
        if (error is RealtimeSubscribeException) {
          message =
              'Realtime sync for $tableName failed: ${error.status} - ${error.details ?? 'no details'} (sync will continue)';
        } else if (error != null) {
          message =
              'Realtime sync for $tableName failed: ${error.toString()} (sync will continue)';
        }
      }
      // Check if this is a specific error type that we can identify
      else if (error is RealtimeSubscribeException) {
        message =
            'Realtime subscription error: ${error.status} - ${error.details ?? 'no details'} (sync will continue)';
        severity = ErrorSeverity.low;
      }
      // For other sync errors, provide more context if available
      else if (error != null) {
        final errorString = error.toString();

        // Add operation context if available
        String operationContext = '';
        if (context != null) {
          if (context.containsKey('operation')) {
            operationContext = ' during ${context['operation']}';
          } else if (context.containsKey('type')) {
            operationContext = ' for ${context['type']}';
          }
        }

        if (errorString.contains('timeout') ||
            errorString.contains('Timeout')) {
          message = 'Sync timeout occurred$operationContext (sync will retry)';
          severity = ErrorSeverity.low;
        } else if (errorString.contains('connection') ||
            errorString.contains('Connection')) {
          message = 'Sync connection issue$operationContext (sync will retry)';
          severity = ErrorSeverity.low;
        } else if (errorString.contains('network') ||
            errorString.contains('Network')) {
          message =
              'Sync network error$operationContext: ${error.toString()} (sync will retry)';
          severity = ErrorSeverity.medium;
        } else if (errorString.contains('permission') ||
            errorString.contains('Permission') ||
            errorString.contains('authentication') ||
            errorString.contains('Authentication')) {
          message =
              'Sync authentication error$operationContext: ${error.toString()}';
          severity = ErrorSeverity.high;
        } else if (errorString.contains('database') ||
            errorString.contains('Database') ||
            errorString.contains('table') ||
            errorString.contains('Table')) {
          message = 'Sync database error$operationContext: ${error.toString()}';
          severity = ErrorSeverity.high;
        } else {
          // Generic error with full details
          message = 'Sync error$operationContext: ${error.toString()}';
          severity = ErrorSeverity.medium;
        }
      }
    } catch (e) {
      // Fallback if error processing itself fails
      message = 'Sync operation failed: unable to process error details';
      severity = ErrorSeverity.medium;
    }

    return {
      'message': message,
      'severity': severity,
    };
  }

  // Internal error logging
  static void _logError(AppError error) {
    // Enhanced console logging with full error details
    final buffer = StringBuffer();
    buffer.writeln('=== ErrorHandler._logError ===');
    buffer.writeln('Message: ${error.message}');
    buffer.writeln('Type: ${error.type}');
    buffer.writeln('Severity: ${error.severity}');

    if (error.originalError != null) {
      buffer.writeln('Original Error: ${error.originalError}');
    }

    if (error.context != null && error.context!.isNotEmpty) {
      buffer.writeln('Context:');
      error.context!.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
    }

    if (error.stackTrace != null) {
      buffer.writeln('Stack Trace:');
      buffer.writeln(error.stackTrace.toString());
    }

    buffer.writeln('=================');

    if (kDebugMode) debugPrint(buffer.toString());

    // Windows-only temporary debug log: write to user's Documents\SelahLogs\selah_debug_YYYY-MM-DD.log
    // remove for production builds
    if (Platform.isWindows) {
      try {
        final userProfile = Platform.environment['USERPROFILE'] ?? '.';
        final logsDir = Directory(
            '$userProfile${Platform.pathSeparator}Documents${Platform.pathSeparator}SelahLogs');
        if (!logsDir.existsSync()) {
          logsDir.createSync(recursive: true);
        }

        final now = DateTime.now();
        final datePart =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final file = File(
            '${logsDir.path}${Platform.pathSeparator}selah_debug_$datePart.log');
        final timestamp = now.toIso8601String();
        final entry = '[$timestamp] ${buffer.toString()}\n';

        file.writeAsStringSync(entry, mode: FileMode.append, flush: true);
      } catch (e) {
        // If file logging fails, fall back to console (do not throw)
        if (kDebugMode) debugPrint('Error writing Windows debug log: $e');
      }
    }
  }

  // Format error message for user display
  static String _formatUserMessage(AppError error) {
    switch (error.type) {
      case ErrorType.network:
        return 'Connection issue: ${error.message}';
      case ErrorType.database:
        return 'Data storage issue: ${error.message}';
      case ErrorType.sync:
        return 'Sync issue: ${error.message}';
      default:
        return 'An error occurred: ${error.message}';
    }
  }

  // Format dynamic error objects to strings
  static String _formatErrorMessage(dynamic error) {
    if (error is String) return error;
    if (error is Exception) {
      return error.toString().replaceFirst('Exception: ', '');
    }
    if (error is Error) return error.toString();
    return error?.toString() ?? 'Unknown error';
  }
}

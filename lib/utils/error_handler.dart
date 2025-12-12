import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
  static Future<void> handleError(AppError error, {BuildContext? context}) async {
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
    final message = 'Sync operation failed';
    await handleError(
        AppError(
          message: message,
          type: ErrorType.sync,
          severity: ErrorSeverity.medium,
          originalError: error,
          stackTrace: StackTrace.current,
          context: context,
        ),
        context: buildContext);
  }

  // Internal error logging
  static void _logError(AppError error) {
    // Basic console logging - could be extended to file logging, crash reporting, etc.
    if (kDebugMode) debugPrint('ErrorHandler _logError: $error');
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
    if (error is Exception) return error.toString().replaceFirst('Exception: ', '');
    if (error is Error) return error.toString();
    return error?.toString() ?? 'Unknown error';
  }
}

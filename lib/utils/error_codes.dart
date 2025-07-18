import 'dart:convert';
import 'package:flutter/foundation.dart'; // Added for debugPrint

enum RegistrationErrorCode {
  usernameTooshort,
  usernameAlreadyTaken,
  emailInvalid,
  emailRequired,
  emailAlreadyRegistered,
  passwordTooshort,
  passwordsDoNotMatch,
  passwordConfirmationMismatch,
  firstNameRequired,
  lastNameRequired,
  networkError,
  timeoutError,
  registrationFailed,
}

class ErrorCodeMapper {
  static const Map<String, RegistrationErrorCode> _codeMap = {
    'USERNAME_TOO_SHORT': RegistrationErrorCode.usernameTooshort,
    'USERNAME_ALREADY_TAKEN': RegistrationErrorCode.usernameAlreadyTaken,
    'EMAIL_INVALID': RegistrationErrorCode.emailInvalid,
    'EMAIL_REQUIRED': RegistrationErrorCode.emailRequired,
    'EMAIL_ALREADY_REGISTERED': RegistrationErrorCode.emailAlreadyRegistered,
    'PASSWORD_TOO_SHORT': RegistrationErrorCode.passwordTooshort,
    'PASSWORDS_DO_NOT_MATCH': RegistrationErrorCode.passwordsDoNotMatch,
    'PASSWORD_CONFIRMATION_MISMATCH':
        RegistrationErrorCode.passwordConfirmationMismatch,
    'FIRST_NAME_REQUIRED': RegistrationErrorCode.firstNameRequired,
    'LAST_NAME_REQUIRED': RegistrationErrorCode.lastNameRequired,
    'NETWORK_ERROR': RegistrationErrorCode.networkError,
    'TIMEOUT_ERROR': RegistrationErrorCode.timeoutError,
    'REGISTRATION_FAILED': RegistrationErrorCode.registrationFailed,
  };

  static const Map<RegistrationErrorCode, String> _messageMap = {
    RegistrationErrorCode.usernameTooshort:
        'Username must be at least 3 characters long.',
    RegistrationErrorCode.usernameAlreadyTaken:
        'Username already taken. Please choose a different username.',
    RegistrationErrorCode.emailInvalid: 'Please enter a valid email address.',
    RegistrationErrorCode.emailRequired: 'Please enter a valid email address.',
    RegistrationErrorCode.emailAlreadyRegistered:
        'Email already registered. Please use a different email or try logging in.',
    RegistrationErrorCode.passwordTooshort:
        'Password must be at least 6 characters long.',
    RegistrationErrorCode.passwordsDoNotMatch:
        'Passwords do not match. Please check and try again.',
    RegistrationErrorCode.passwordConfirmationMismatch:
        'Password confirmation does not match.',
    RegistrationErrorCode.firstNameRequired: 'Please enter your first name.',
    RegistrationErrorCode.lastNameRequired: 'Please enter your last name.',
    RegistrationErrorCode.networkError:
        'Network error. Please check your connection and try again.',
    RegistrationErrorCode.timeoutError:
        'Registration timed out. Please try again.',
    RegistrationErrorCode.registrationFailed:
        'Registration failed. Please check your information and try again.',
  };

  /// Convert server error code string to enum
  static RegistrationErrorCode? fromString(String? errorCode) {
    if (errorCode == null) return null;
    return _codeMap[errorCode];
  }

  /// Get user-friendly error message from error code
  static String getMessage(RegistrationErrorCode errorCode) {
    return _messageMap[errorCode] ??
        'An unexpected error occurred. Please try again.';
  }

  /// Parse error from server response and return user-friendly message
  static String parseErrorMessage(dynamic errorResponse) {
    debugPrint('🐛 ERROR_DEBUG: Raw error response: $errorResponse');
    debugPrint(
      '🐛 ERROR_DEBUG: Error response type: ${errorResponse.runtimeType}',
    );
    debugPrint(
      '🐛 ERROR_DEBUG: Error response toString: ${errorResponse.toString()}',
    );

    // For HTTP exceptions, we need to extract the response body
    String responseBody = '';

    if (errorResponse.toString().contains('Exception:') &&
        errorResponse.toString().contains('{')) {
      // Extract JSON from exception string
      final jsonMatch = RegExp(
        r'\{[^}]*\}',
      ).firstMatch(errorResponse.toString());
      if (jsonMatch != null) {
        responseBody = jsonMatch.group(0)!;
        debugPrint(
          '🐛 ERROR_DEBUG: Extracted JSON from exception: $responseBody',
        );
      }
    } else if (errorResponse is String) {
      responseBody = errorResponse;
    } else {
      debugPrint(
        '🐛 ERROR_DEBUG: Could not extract response body, using toString',
      );
      responseBody = errorResponse.toString();
    }

    try {
      // Try to parse the response body as JSON
      debugPrint('🐛 ERROR_DEBUG: Attempting to parse: $responseBody');
      final Map<String, dynamic> errorData = Map<String, dynamic>.from(
        const JsonCodec().decode(responseBody),
      );

      debugPrint('🐛 ERROR_DEBUG: Parsed error data: $errorData');

      // Check for error code first
      if (errorData.containsKey('errorCode')) {
        debugPrint(
          '🐛 ERROR_DEBUG: Found errorCode: ${errorData['errorCode']}',
        );
        final errorCode = fromString(errorData['errorCode']);
        if (errorCode != null) {
          debugPrint('🐛 ERROR_DEBUG: Mapped to enum: $errorCode');
          final message = getMessage(errorCode);
          debugPrint('🐛 ERROR_DEBUG: Final message: $message');
          return message;
        }
      }

      // Fallback to message field
      if (errorData.containsKey('message')) {
        debugPrint(
          '🐛 ERROR_DEBUG: Using message field: ${errorData['message']}',
        );
        return errorData['message'].toString();
      }
    } catch (e) {
      debugPrint('🐛 ERROR_DEBUG: JSON parsing failed: $e');
      // If JSON parsing fails, use string fallback
      return _parseErrorStringFallback(responseBody);
    }

    debugPrint('🐛 ERROR_DEBUG: No valid error found, using generic message');
    return 'Registration failed. Please try again.';
  }

  /// Fallback string parsing for backward compatibility
  static String _parseErrorStringFallback(String errorString) {
    final lowerError = errorString.toLowerCase();

    if (lowerError.contains('username already taken') ||
        (lowerError.contains('username') && lowerError.contains('already'))) {
      return getMessage(RegistrationErrorCode.usernameAlreadyTaken);
    } else if (lowerError.contains('username') &&
        lowerError.contains('at least') &&
        lowerError.contains('characters')) {
      return getMessage(RegistrationErrorCode.usernameTooshort);
    } else if (lowerError.contains('email already registered') ||
        (lowerError.contains('email') && lowerError.contains('already'))) {
      return getMessage(RegistrationErrorCode.emailAlreadyRegistered);
    } else if (lowerError.contains('valid email') ||
        (lowerError.contains('email') && lowerError.contains('required'))) {
      return getMessage(RegistrationErrorCode.emailInvalid);
    } else if (lowerError.contains('password')) {
      return getMessage(RegistrationErrorCode.passwordTooshort);
    } else if (lowerError.contains('passwords') &&
        lowerError.contains('match')) {
      return getMessage(RegistrationErrorCode.passwordsDoNotMatch);
    } else if (lowerError.contains('password') &&
        lowerError.contains('confirm')) {
      return getMessage(RegistrationErrorCode.passwordConfirmationMismatch);
    } else if (lowerError.contains('first name') &&
        lowerError.contains('required')) {
      return getMessage(RegistrationErrorCode.firstNameRequired);
    } else if (lowerError.contains('last name') &&
        lowerError.contains('required')) {
      return getMessage(RegistrationErrorCode.lastNameRequired);
    } else if (lowerError.contains('connection') ||
        lowerError.contains('network')) {
      return getMessage(RegistrationErrorCode.networkError);
    } else if (lowerError.contains('timeout')) {
      return getMessage(RegistrationErrorCode.timeoutError);
    } else {
      return getMessage(RegistrationErrorCode.registrationFailed);
    }
  }
}

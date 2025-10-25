class AppException implements Exception {
  final String message;
  final Object? cause;
  AppException(this.message, {this.cause});

  @override
  String toString() => 'AppException($message)';
}

class PermissionDeniedException extends AppException {
  PermissionDeniedException(String message) : super(message);
}

class BluetoothDisabledException extends AppException {
  BluetoothDisabledException(String message) : super(message);
}

class ConnectionException extends AppException {
  ConnectionException(String message, {Object? cause}) : super(message, cause: cause);
}
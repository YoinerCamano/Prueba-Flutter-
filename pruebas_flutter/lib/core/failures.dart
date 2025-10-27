import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);
  @override
  List<Object?> get props => [message];
}

class PermissionFailure extends Failure { const PermissionFailure(String m) : super(m); }
class ConnectionFailure extends Failure { const ConnectionFailure(String m) : super(m); }
class OperationFailure extends Failure { const OperationFailure(String m) : super(m); }

part of 'connection_bloc.dart';

abstract class ConnectionEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class ConnectRequested extends ConnectionEvent {
  final BtDevice device;
  ConnectRequested(this.device);
  @override
  List<Object?> get props => [device];
}

class DisconnectRequested extends ConnectionEvent {}

class RawLineArrived extends ConnectionEvent {
  final String line;
  RawLineArrived(this.line);
  @override
  List<Object?> get props => [line];
}

class SendCommandRequested extends ConnectionEvent {
  final String command;
  SendCommandRequested(this.command);
  @override
  List<Object?> get props => [command];
}

class StartPolling extends ConnectionEvent {}

class StopPolling extends ConnectionEvent {}

/// Nuevo evento para verificar conexiones manuales
class CheckManualConnectionRequested extends ConnectionEvent {
  final BtDevice device;
  CheckManualConnectionRequested(this.device);
  @override
  List<Object?> get props => [device];
}

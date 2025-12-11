part of 'connection_bloc.dart';

/// Enum para comandos de la báscula con mayor claridad y type-safety
enum ScaleCommand {
  readWeight('{RW}'),
  batteryVoltage('{BV}'),
  batteryCapacity('{BC}'),
  serialNumber('{TTCSER}'),
  firmwareVersion('{VA}'),
  cellCode('{SACC}'),
  cellSpecifications('{SCLS}'),
  resetZero('{SCZERO}'),
  adcNoise('{SCAV}'),
  weightUnit('{SPWU}'),
  setUnitKg('{SPWU0}'),
  setUnitLb('{SPWU1}'),
  enableAcknowledgment('{ZA1}'), // Habilita respuestas de confirmación "^"
  getErrors('{ZE1}'), // Obtener errores de la báscula
  setCarriageReturn('{ZC1}'); // Establecer retorno de carro

  const ScaleCommand(this.code);
  final String code;
}

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

/// Nuevo evento para detectar conexiones automáticas al iniciar
class CheckAutoConnectionRequested extends ConnectionEvent {}

/// Timeout de inicialización (ZA1 / SPWU)
class InitTimeoutExpired extends ConnectionEvent {
  final int step;
  InitTimeoutExpired(this.step);
  @override
  List<Object?> get props => [step];
}

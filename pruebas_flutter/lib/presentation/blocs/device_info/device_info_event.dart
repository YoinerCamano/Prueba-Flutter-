part of 'device_info_bloc.dart';

abstract class DeviceInfoEvent extends Equatable {
  const DeviceInfoEvent();
  @override
  List<Object?> get props => [];
}

class DeviceInfoStartListening extends DeviceInfoEvent {
  const DeviceInfoStartListening();
}

class DeviceInfoStopListening extends DeviceInfoEvent {
  const DeviceInfoStopListening();
}

class DeviceInfoSendCommandRequested extends DeviceInfoEvent {
  final String command;
  const DeviceInfoSendCommandRequested(this.command);
  @override
  List<Object?> get props => [command];
}

class DeviceInfoRawLineArrived extends DeviceInfoEvent {
  final String line;
  const DeviceInfoRawLineArrived(this.line);
  @override
  List<Object?> get props => [line];
}

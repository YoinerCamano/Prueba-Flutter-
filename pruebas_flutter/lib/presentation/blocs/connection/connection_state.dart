part of 'connection_bloc.dart';

abstract class ConnectionState extends Equatable {
  const ConnectionState();
  @override
  List<Object?> get props => [];
  const factory ConnectionState.disconnected() = Disconnected;
  factory ConnectionState.connecting({required BtDevice device}) = Connecting;
  factory ConnectionState.connected({required BtDevice device}) = Connected;
  factory ConnectionState.error(String message) = ConnectionError;
}

class Disconnected extends ConnectionState {
  const Disconnected();
}

class Connecting extends ConnectionState {
  final BtDevice device;
  const Connecting({required this.device});
  @override
  List<Object?> get props => [device];
}

class Connected extends ConnectionState {
  final BtDevice device;
  final WeightReading? weight;
  final BatteryStatus? battery;
  const Connected({required this.device, this.weight, this.battery});

  Connected copyWith({WeightReading? weight, BatteryStatus? battery}) =>
      Connected(device: device, weight: weight ?? this.weight, battery: battery ?? this.battery);

  @override
  List<Object?> get props => [device, weight, battery];
}

class ConnectionError extends ConnectionState {
  final String message;
  const ConnectionError(this.message);
  @override
  List<Object?> get props => [message];
}

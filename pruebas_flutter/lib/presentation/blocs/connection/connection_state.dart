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
  final BatteryStatus? batteryVoltage; // Para voltaje {BV}
  final BatteryStatus? batteryPercent; // Para porcentaje {BC}
  const Connected(
      {required this.device,
      this.weight,
      this.batteryVoltage,
      this.batteryPercent});

  Connected copyWith(
          {WeightReading? weight,
          BatteryStatus? batteryVoltage,
          BatteryStatus? batteryPercent}) =>
      Connected(
          device: device,
          weight: weight ?? this.weight,
          batteryVoltage: batteryVoltage ?? this.batteryVoltage,
          batteryPercent: batteryPercent ?? this.batteryPercent);

  @override
  List<Object?> get props => [device, weight, batteryVoltage, batteryPercent];
}

class ConnectionError extends ConnectionState {
  final String message;
  const ConnectionError(this.message);
  @override
  List<Object?> get props => [message];
}

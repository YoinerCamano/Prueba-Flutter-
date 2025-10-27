import 'package:equatable/equatable.dart';

class BtDevice extends Equatable {
  final String id;   // MAC (SPP) o deviceId (BLE)
  final String name;
  const BtDevice({required this.id, required this.name});
  @override
  List<Object?> get props => [id, name];
}

class WeightReading extends Equatable {
  final double? kg;
  final DateTime at;
  const WeightReading({required this.kg, required this.at});
  @override
  List<Object?> get props => [kg, at];
}

class BatteryStatus extends Equatable {
  final double? volts;
  final double? percent;
  final DateTime at;
  const BatteryStatus({this.volts, this.percent, required this.at});
  @override
  List<Object?> get props => [volts, percent, at];
}

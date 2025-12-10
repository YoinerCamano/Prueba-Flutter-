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

  // 🔧 Información técnica del dispositivo
  final String? serialNumber; // {TTCSER}
  final String? firmwareVersion; // {VA}
  final String? cellCode; // {SACC}
  final String? cellLoadmVV; // {SCLS} - Primer valor
  final String? microvoltsPerDivision; // {SCLS} - Segundo valor
  final String? adcNoise; // {SCAV} - Ruido CAD (conversor A/D)
  final String? weightUnit; // {MSWU} - Unidad de peso configurada (kg/lb)

  const Connected({
    required this.device,
    this.weight,
    this.batteryVoltage,
    this.batteryPercent,
    this.serialNumber,
    this.firmwareVersion,
    this.cellCode,
    this.cellLoadmVV,
    this.microvoltsPerDivision,
    this.adcNoise,
    this.weightUnit,
  });

  Connected copyWith({
    WeightReading? weight,
    BatteryStatus? batteryVoltage,
    BatteryStatus? batteryPercent,
    String? serialNumber,
    String? firmwareVersion,
    String? cellCode,
    String? cellLoadmVV,
    String? microvoltsPerDivision,
    String? adcNoise,
    String? weightUnit,
  }) =>
      Connected(
        device: device,
        weight: weight ?? this.weight,
        batteryVoltage: batteryVoltage ?? this.batteryVoltage,
        batteryPercent: batteryPercent ?? this.batteryPercent,
        serialNumber: serialNumber ?? this.serialNumber,
        firmwareVersion: firmwareVersion ?? this.firmwareVersion,
        cellCode: cellCode ?? this.cellCode,
        cellLoadmVV: cellLoadmVV ?? this.cellLoadmVV,
        microvoltsPerDivision:
            microvoltsPerDivision ?? this.microvoltsPerDivision,
        adcNoise: adcNoise ?? this.adcNoise,
        weightUnit: weightUnit ?? this.weightUnit,
      );

  @override
  List<Object?> get props => [
        device,
        weight,
        batteryVoltage,
        batteryPercent,
        serialNumber,
        firmwareVersion,
        cellCode,
        cellLoadmVV,
        microvoltsPerDivision,
        adcNoise,
        weightUnit,
      ];
}

class ConnectionError extends ConnectionState {
  final String message;
  const ConnectionError(this.message);
  @override
  List<Object?> get props => [message];
}

part of 'device_info_bloc.dart';

class DeviceInfoState extends Equatable {
  final BatteryStatus? batteryVoltage;
  final BatteryStatus? batteryPercent;
  final String? serialNumber;
  final String? firmwareVersion;
  final String? cellCode;
  final String? cellLoadmVV;
  final String? microvoltsPerDivision;
  final String? adcNoise;

  const DeviceInfoState({
    this.batteryVoltage,
    this.batteryPercent,
    this.serialNumber,
    this.firmwareVersion,
    this.cellCode,
    this.cellLoadmVV,
    this.microvoltsPerDivision,
    this.adcNoise,
  });

  DeviceInfoState copyWith({
    BatteryStatus? batteryVoltage,
    BatteryStatus? batteryPercent,
    String? serialNumber,
    String? firmwareVersion,
    String? cellCode,
    String? cellLoadmVV,
    String? microvoltsPerDivision,
    String? adcNoise,
  }) {
    return DeviceInfoState(
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      serialNumber: serialNumber ?? this.serialNumber,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      cellCode: cellCode ?? this.cellCode,
      cellLoadmVV: cellLoadmVV ?? this.cellLoadmVV,
      microvoltsPerDivision:
          microvoltsPerDivision ?? this.microvoltsPerDivision,
      adcNoise: adcNoise ?? this.adcNoise,
    );
  }

  @override
  List<Object?> get props => [
        batteryVoltage,
        batteryPercent,
        serialNumber,
        firmwareVersion,
        cellCode,
        cellLoadmVV,
        microvoltsPerDivision,
        adcNoise,
      ];
}

import 'package:pruebas_flutter/domain/repositories/ble_repository.dart';

class DisconnectDevice {
  final BleRepository repository;
  DisconnectDevice(this.repository);

  Future<void> call(String deviceId) => repository.disconnect(deviceId);
}
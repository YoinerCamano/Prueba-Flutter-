import 'package:pruebas_flutter/domain/repositories/ble_repository.dart';

class ConnectDevice {
  final BleRepository repository;
  ConnectDevice(this.repository);

  Future<void> call(String deviceId) => repository.connect(deviceId);
}
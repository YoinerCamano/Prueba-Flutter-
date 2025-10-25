import 'package:pruebas_flutter/domain/entities/ble_device.dart';
import 'package:pruebas_flutter/domain/repositories/ble_repository.dart';

class ScanDevices {
  final BleRepository repository;
  ScanDevices(this.repository);

  Stream<List<BleDevice>> call() => repository.scan();
  Future<void> stop() => repository.stopScan();
}
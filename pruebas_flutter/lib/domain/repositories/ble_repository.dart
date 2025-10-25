import 'package:pruebas_flutter/domain/entities/ble_device.dart';

abstract class BleRepository {
  Stream<List<BleDevice>> scan();
  Future<void> stopScan();

  Future<void> connect(String deviceId);
  Future<void> disconnect(String deviceId);

  Stream<bool> connectionState(String deviceId);
}
import 'dart:async';
import 'entities.dart';

abstract class BluetoothRepository {
  Future<List<BtDevice>> scanNearby({Duration timeout});
  Future<List<BtDevice>> bondedDevices();
  Future<void> connect(String id);
  Future<void> disconnect();
  Stream<String> rawStream();
  Future<void> sendCommand(String command);
  Future<bool> isConnected();
}

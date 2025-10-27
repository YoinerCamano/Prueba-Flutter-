import '../../domain/bluetooth_repository.dart';
import '../../domain/entities.dart';
import 'ble_adapter.dart';

class BluetoothRepositoryBle implements BluetoothRepository {
  final BleAdapter adapter;
  BluetoothRepositoryBle(this.adapter);

  @override
  Future<List<BtDevice>> scanNearby({Duration timeout = const Duration(seconds: 8)}) async {
    final res = await adapter.scan(timeout: timeout);
    return res.map((d) => BtDevice(id: d.id, name: d.name.isNotEmpty ? d.name : d.id)).toList();
  }

  @override
  Future<List<BtDevice>> bondedDevices() async => [];

  @override
  Future<void> connect(String id) => adapter.connect(id);
  @override
  Future<void> disconnect() => adapter.disconnect();
  @override
  Stream<String> rawStream() => adapter.lines;
  @override
  Future<void> sendCommand(String command) => adapter.writeLine(command);
  @override
  Future<bool> isConnected() => adapter.isConnected();
}

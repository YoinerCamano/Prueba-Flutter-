import '../../domain/bluetooth_repository.dart';
import '../../domain/entities.dart';
import 'ble_adapter.dart';

class BluetoothRepositoryBle implements BluetoothRepository {
  final BleAdapter adapter;
  BluetoothRepositoryBle(this.adapter);

  @override
  Future<List<BtDevice>> scanNearby(
      {Duration timeout = const Duration(seconds: 8)}) async {
    print('🔍 === ESCANEO BLE ===');
    final res = await adapter.scan(timeout: timeout);
    print('📡 Dispositivos BLE encontrados: ${res.length}');

    final devices = res
        .map((d) => BtDevice(id: d.id, name: d.name.isNotEmpty ? d.name : d.id))
        .toList();

    // Buscar específicamente la S3
    for (final device in devices) {
      if (device.id.toUpperCase().contains('DE:FD:76:A4:D7:ED')) {
        print('⚖️ *** BÁSCULA S3 ENCONTRADA VIA BLE ***');
        print('🎯 ID: ${device.id}');
        print('🏷️ Nombre: ${device.name}');
      }
    }

    return devices;
  }

  @override
  Future<List<BtDevice>> bondedDevices() async {
    print('🔍 === OBTENIENDO DISPOSITIVOS BLE (EMPAREJADOS) ===');
    // Para BLE, normalmente no hay "emparejamiento" tradicional
    // Pero podemos hacer un escaneo rápido para encontrar dispositivos conocidos
    return await scanNearby(timeout: const Duration(seconds: 3));
  }

  @override
  Future<void> connect(String id) async {
    print('🔗 === CONECTANDO VIA BLE ===');
    print('🎯 Dispositivo: $id');
    await adapter.connect(id);
    print('✅ Conexión BLE establecida');
  }

  @override
  Future<void> disconnect() async {
    print('🔌 Desconectando BLE...');
    await adapter.disconnect();
  }

  @override
  Stream<String> rawStream() => adapter.lines;

  @override
  Future<void> sendCommand(String command) async {
    print('📤 Enviando comando BLE: $command');
    await adapter.writeLine(command);
  }

  @override
  Future<bool> isConnected() async => await adapter.isConnected();
}

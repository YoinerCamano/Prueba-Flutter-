import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

// Test rápido para verificar dispositivos emparejados
void main() async {
  print('🔍 TEST: Verificando dispositivos emparejados...');

  final bt = FlutterBluetoothSerial.instance;
  final devices = await bt.getBondedDevices();

  print('📋 Total dispositivos: ${devices.length}');

  for (int i = 0; i < devices.length; i++) {
    final device = devices[i];
    print('📱 [$i] ${device.name ?? 'Sin nombre'} (${device.address})');

    if (device.address == 'DE:FD:76:A4:D7:ED') {
      print('⚖️  *** S3 ENCONTRADA ***');
    }
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

/// Utilidades de debugging específicas para Bluetooth
class BluetoothDebug {
  /// Ejecuta un diagnóstico completo del sistema Bluetooth
  static Future<void> runFullDiagnostic() async {
    print('');
    print('🔍 ================================');
    print('🔍 === DIAGNÓSTICO BLUETOOTH ===');
    print('🔍 ================================');
    print('');

    // 1. Información del sistema
    await _checkSystemInfo();

    // 2. Estado de permisos
    await _checkPermissions();

    // 3. Estado de Bluetooth
    await _checkBluetoothState();

    // 4. Dispositivos emparejados
    await _checkBondedDevices();

    print('');
    print('🔍 ================================');
    print('🔍 === FIN DIAGNÓSTICO ===');
    print('🔍 ================================');
    print('');
  }

  static Future<void> _checkSystemInfo() async {
    print('📱 === INFORMACIÓN DEL SISTEMA ===');
    print('🤖 Plataforma: ${Platform.operatingSystem}');
    print('📋 Versión: ${Platform.operatingSystemVersion}');
    print('');
  }

  static Future<void> _checkPermissions() async {
    print('🔐 === ESTADO DE PERMISOS ===');

    final permissions = [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.location,
      Permission.locationWhenInUse,
    ];

    for (final perm in permissions) {
      try {
        final status = await perm.status;
        print('🔹 ${perm.toString()}:');
        print('   Estado: $status');
      } catch (e) {
        print('🔹 ${perm.toString()}: ERROR - $e');
      }
    }
    print('');
  }

  static Future<void> _checkBluetoothState() async {
    print('📡 === ESTADO DE BLUETOOTH ===');

    try {
      final bluetooth = FlutterBluetoothSerial.instance;
      final state = await bluetooth.state;
      print('🔹 Estado actual: $state');

      final isEnabled = await bluetooth.isEnabled;
      print('🔹 Habilitado: $isEnabled');

      final isAvailable = await bluetooth.isAvailable;
      print('🔹 Disponible: $isAvailable');

      final name = await bluetooth.name;
      print('🔹 Nombre del dispositivo: $name');

      final address = await bluetooth.address;
      print('🔹 Dirección MAC: $address');
    } catch (e) {
      print('❌ Error verificando estado de Bluetooth: $e');
    }
    print('');
  }

  static Future<void> _checkBondedDevices() async {
    print('🔗 === DISPOSITIVOS EMPAREJADOS ===');

    try {
      final bluetooth = FlutterBluetoothSerial.instance;
      final devices = await bluetooth.getBondedDevices();

      print('📊 Total dispositivos: ${devices.length}');

      if (devices.isEmpty) {
        print('❌ NO HAY DISPOSITIVOS EMPAREJADOS');
        print(
            '💡 Solución: Ir a Configuración > Bluetooth y emparejar la báscula');
      } else {
        for (int i = 0; i < devices.length; i++) {
          final device = devices[i];
          print('');
          print('📱 [$i] ${device.name ?? 'Sin nombre'}');
          print('   📍 MAC: ${device.address}');
          print('   🔧 Tipo: ${device.type}');

          // Verificar si es una S3
          if (device.address == 'DE:FD:76:A4:D7:ED') {
            print('   ⚖️  *** BÁSCULA S3 DETECTADA (MAC CONOCIDA) ***');
          } else if (device.name?.contains('S3') == true ||
              device.name?.contains('680066') == true) {
            print('   ⚖️  *** POSIBLE BÁSCULA S3 DETECTADA (NOMBRE) ***');
          }
        }
      }
    } catch (e) {
      print('❌ Error obteniendo dispositivos emparejados: $e');
    }
    print('');
  }

  /// Prueba de conexión específica para la S3
  static Future<void> testS3Connection(String macAddress) async {
    print('');
    print('🧪 === PRUEBA DE CONEXIÓN S3 ===');
    print('🎯 MAC: $macAddress');
    print('');

    try {
      print('1️⃣ Intentando conexión...');
      final connection = await BluetoothConnection.toAddress(macAddress);

      print('✅ Conexión establecida');
      print('🔗 Estado: ${connection.isConnected}');

      print('2️⃣ Enviando comando de prueba...');
      connection.output.add(Uint8List.fromList([13, 10])); // \r\n
      await connection.output.allSent;

      print('3️⃣ Esperando respuesta (5 segundos)...');
      bool received = false;
      connection.input?.listen((data) {
        print('📥 Respuesta recibida: $data');
        received = true;
      });

      await Future.delayed(const Duration(seconds: 5));

      if (!received) {
        print('⚠️ No se recibió respuesta');
      }

      print('4️⃣ Cerrando conexión...');
      await connection.finish();
      print('✅ Conexión cerrada');
    } catch (e) {
      print('❌ Error en prueba de conexión: $e');
    }

    print('');
    print('🧪 === FIN PRUEBA ===');
    print('');
  }
}

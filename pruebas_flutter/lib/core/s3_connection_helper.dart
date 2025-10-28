import 'dart:async';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// Utilidades específicas para mejorar la conexión con Tru-Test S3
class S3ConnectionHelper {
  /// Intenta conectar a la S3 con múltiples estrategias
  static Future<BluetoothConnection> connectWithRetries(String address) async {
    print('🔗 === CONEXIÓN MEJORADA PARA S3 ===');
    print('🎯 MAC: $address');

    final bt = FlutterBluetoothSerial.instance;

    // Asegurar que BT esté encendido
    final state = await bt.state;
    if (state != BluetoothState.STATE_ON) {
      await bt.requestEnable();
      await Future.delayed(const Duration(seconds: 3));
    }

    // Cancelar discovery múltiples veces
    for (int i = 0; i < 3; i++) {
      try {
        await bt.cancelDiscovery();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (_) {}
    }

    BluetoothConnection? connection;
    Exception? lastError;

    // INTENTO 1: Conexión directa con timeout corto
    print('🚀 Intento 1: Conexión directa...');
    try {
      await Future.delayed(const Duration(seconds: 2));
      connection = await BluetoothConnection.toAddress(address).timeout(
        const Duration(seconds: 8),
      );

      if (connection.isConnected) {
        print('✅ Intento 1 exitoso');
        return connection;
      } else {
        throw Exception('Socket no conectado');
      }
    } catch (e) {
      print('❌ Intento 1 falló: $e');
      lastError = e is Exception ? e : Exception(e.toString());
      try {
        await connection?.finish();
      } catch (_) {}
    }

    // INTENTO 2: Con pausa más larga
    print('🚀 Intento 2: Con pausa larga...');
    try {
      await Future.delayed(const Duration(seconds: 5));
      connection = await BluetoothConnection.toAddress(address).timeout(
        const Duration(seconds: 12),
      );

      if (connection.isConnected) {
        print('✅ Intento 2 exitoso');
        return connection;
      } else {
        throw Exception('Socket no conectado en intento 2');
      }
    } catch (e) {
      print('❌ Intento 2 falló: $e');
      lastError = e is Exception ? e : Exception(e.toString());
      try {
        await connection?.finish();
      } catch (_) {}
    }

    // INTENTO 3: Reset y pausa larga
    print('🚀 Intento 3: Con reset...');
    try {
      // Múltiples cancelaciones para limpiar
      for (int i = 0; i < 5; i++) {
        try {
          await bt.cancelDiscovery();
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (_) {}
      }

      await Future.delayed(const Duration(seconds: 8));
      connection = await BluetoothConnection.toAddress(address).timeout(
        const Duration(seconds: 15),
      );

      if (connection.isConnected) {
        print('✅ Intento 3 exitoso');
        return connection;
      } else {
        throw Exception('Socket no conectado en intento 3');
      }
    } catch (e) {
      print('❌ Intento 3 falló: $e');
      lastError = e is Exception ? e : Exception(e.toString());
      try {
        await connection?.finish();
      } catch (_) {}
    }

    // Todos los intentos fallaron
    print('❌ TODOS LOS INTENTOS FALLARON');
    print('💡 SOLUCIONES:');
    print('1. Reinicia la báscula S3 (apagar/encender)');
    print('2. Olvida y vuelve a emparejar el dispositivo');
    print('3. Verifica que no esté conectada a otro dispositivo');
    print('4. Mantén la báscula cerca (< 1 metro)');

    throw Exception(
        'No se pudo conectar después de 3 intentos. Último error: $lastError');
  }
}

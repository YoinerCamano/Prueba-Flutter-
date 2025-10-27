// Versión simplificada con parámetros específicos para Tru-Test S3
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../domain/bluetooth_repository.dart';
import '../domain/entities.dart';

/// Adaptador para Bluetooth Clásico (SPP) optimizado para Tru-Test S3
class BluetoothAdapterSpp {
  final FlutterBluetoothSerial _bt = FlutterBluetoothSerial.instance;

  BluetoothConnection? _connection;
  final _controller = StreamController<String>.broadcast();
  StreamSubscription<Uint8List>? _inputSub;
  final _lineBuffer = StringBuffer();
  bool _isConnecting = false;

  /// Garantiza que el BT está encendido
  Future<void> ensureOn() async {
    final state = await _bt.state;
    print('Estado de Bluetooth: $state');

    if (state != BluetoothState.STATE_ON) {
      print('Activando Bluetooth...');
      final result = await _bt.requestEnable();
      if (result != true) {
        throw Exception('Bluetooth no se pudo activar');
      }
      await Future.delayed(const Duration(milliseconds: 2000));
    }
  }

  /// Lista dispositivos emparejados
  Future<List<BluetoothDevice>> bonded() async {
    await ensureOn();
    return _bt.getBondedDevices();
  }

  /// Conecta específicamente optimizado para Tru-Test S3
  Future<void> connect(String address) async {
    if (_isConnecting) {
      print('Conexión ya en progreso');
      return;
    }

    if (_connection?.isConnected == true) {
      print('Ya conectado');
      return;
    }

    _isConnecting = true;
    print('=== CONEXIÓN ESPECÍFICA PARA TRU-TEST S3 ===');

    try {
      await ensureOn();

      // Limpieza específica para S3
      await disconnect();
      for (int i = 0; i < 5; i++) {
        try {
          await _bt.cancelDiscovery();
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (_) {}
      }

      // Espera larga específica para S3
      await Future.delayed(const Duration(milliseconds: 5000));

      print('Iniciando conexión RFCOMM para S3...');
      final conn = await BluetoothConnection.toAddress(address);
      _connection = conn;
      print('✅ Conectado a Tru-Test S3');

      // Configurar escucha con parámetros específicos para S3
      _inputSub = conn.input?.listen(
        (Uint8List data) {
          final chunk = utf8.decode(data, allowMalformed: true);
          _lineBuffer.write(chunk);
          final parts = _lineBuffer.toString().split(RegExp(r'\r?\n'));

          for (int i = 0; i < parts.length - 1; i++) {
            final line = parts[i].trim();
            if (line.isNotEmpty) {
              print('S3 → $line');
              _controller.add(line);
            }
          }

          _lineBuffer
            ..clear()
            ..write(parts.last);
        },
        onDone: () {
          print('S3 desconectado');
          _controller.add('__DISCONNECTED__');
        },
        onError: (e) {
          print('Error S3: $e');
          _controller.add('__ERROR__: $e');
        },
      );

      // Inicialización específica para S3
      await Future.delayed(const Duration(milliseconds: 2000));
      try {
        print('Enviando comando wake-up a S3...');
        conn.output.add(utf8.encode('\r\n'));
        await conn.output.allSent;
      } catch (e) {
        print('Advertencia comando wake-up: $e');
      }
    } catch (e) {
      print('Error conectando a S3: $e');
      throw Exception('Error conectando a Tru-Test S3: $e\n\n'
          'Soluciones:\n'
          '1. Apague y encienda la báscula\n'
          '2. Mantenga la báscula cerca del dispositivo\n'
          '3. Verifique que no hay interferencias');
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    await _inputSub?.cancel();
    _inputSub = null;
    await _connection?.finish();
    _connection = null;
    _lineBuffer.clear();
  }

  Future<void> writeLine(String line) async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      throw StateError('No conectado a S3');
    }
    print('Enviando a S3: $line');
    conn.output.add(utf8.encode('$line\r\n'));
    await conn.output.allSent;
  }

  Stream<String> get lines => _controller.stream;
  Future<bool> isConnected() async => _connection?.isConnected == true;
}

/// Repositorio específico para Tru-Test S3
class BluetoothRepositorySpp implements BluetoothRepository {
  final BluetoothAdapterSpp adapter;
  BluetoothRepositorySpp(this.adapter);

  @override
  Future<List<BtDevice>> scanNearby(
      {Duration timeout = const Duration(seconds: 8)}) async {
    // Para S3, usar solo dispositivos emparejados
    final bonded = await adapter.bonded();
    return bonded
        .map((d) => BtDevice(
            id: d.address,
            name: d.name?.isNotEmpty == true ? d.name! : d.address))
        .toList();
  }

  @override
  Future<List<BtDevice>> bondedDevices() async {
    final devices = await adapter.bonded();
    return devices
        .map((d) => BtDevice(
            id: d.address,
            name: d.name?.isNotEmpty == true ? d.name! : d.address))
        .toList();
  }

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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../core/s3_connection_helper.dart';
import '../domain/bluetooth_repository.dart';
import '../domain/entities.dart';

/// Versión mejorada del adaptador SPP para Tru-Test S3
class BluetoothAdapterSppImproved {
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
    print('🔍 === OBTENIENDO DISPOSITIVOS EMPAREJADOS ===');
    await ensureOn();

    final devices = await _bt.getBondedDevices();
    print('📋 Total dispositivos emparejados encontrados: ${devices.length}');

    for (int i = 0; i < devices.length; i++) {
      final device = devices[i];
      final name = device.name ?? 'Sin nombre';
      final address = device.address;
      print('📱 [$i] $name ($address)');

      if (address == 'DE:FD:76:A4:D7:ED') {
        print('⚖️  *** BÁSCULA S3 ENCONTRADA ***');
      }
    }

    return devices;
  }

  /// Conexión mejorada para S3 usando el helper
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

    try {
      await ensureOn();
      await disconnect(); // Limpiar conexiones previas

      // Usar el helper para la conexión mejorada
      print('🔗 Usando estrategia de conexión mejorada...');
      final conn = await S3ConnectionHelper.connectWithRetries(address);

      _connection = conn;

      // Configurar listener
      print('🎧 Configurando listener de datos...');
      _inputSub = conn.input?.listen(
        (Uint8List data) {
          final chunk = utf8.decode(data, allowMalformed: true);
          print(
              '📥 Raw data S3: "${chunk.replaceAll('\r', '\\r').replaceAll('\n', '\\n')}"');

          _lineBuffer.write(chunk);
          final parts = _lineBuffer.toString().split(RegExp(r'\r?\n'));

          for (int i = 0; i < parts.length - 1; i++) {
            final line = parts[i].trim();
            if (line.isNotEmpty) {
              print('📊 Línea S3: "$line"');
              _controller.add(line);
            }
          }

          _lineBuffer
            ..clear()
            ..write(parts.last);
        },
        onDone: () {
          print('🔌 Conexión S3 terminada');
          _controller.add('__DISCONNECTED__');
        },
        onError: (e) {
          print('❌ Error en datos S3: $e');
          _controller.add('__ERROR__: $e');
        },
      );

      // Wake-up inicial
      print('⏳ Pausa antes del wake-up (2 segundos)...');
      await Future.delayed(const Duration(milliseconds: 2000));

      try {
        print('📤 Enviando wake-up...');
        conn.output.add(utf8.encode('\r\n'));
        await conn.output.allSent;
        print('✅ Wake-up enviado');
      } catch (e) {
        print('⚠️ Error en wake-up: $e');
      }

      print('🎉 *** CONEXIÓN S3 EXITOSA ***');
    } catch (e) {
      print('❌ Error en conexión: $e');
      throw Exception('Error conectando a S3: $e');
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

    print('📤 Enviando comando: "$line"');
    try {
      conn.output.add(utf8.encode('$line\r\n'));
      await conn.output.allSent;
      print('✅ Comando enviado');
    } catch (e) {
      print('❌ Error enviando comando: $e');
      throw StateError('Error enviando comando: $e');
    }
  }

  Stream<String> get lines => _controller.stream;
  Future<bool> isConnected() async => _connection?.isConnected == true;
}

/// Repositorio mejorado para S3
class BluetoothRepositorySppImproved implements BluetoothRepository {
  final BluetoothAdapterSppImproved adapter;
  BluetoothRepositorySppImproved(this.adapter);

  @override
  Future<List<BtDevice>> scanNearby(
      {Duration timeout = const Duration(seconds: 8)}) async {
    print('🔍 === ESCANEO MEJORADO ===');

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

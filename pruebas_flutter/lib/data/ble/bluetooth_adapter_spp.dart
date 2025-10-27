import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class BluetoothAdapterSpp {
  final FlutterBluetoothSerial _bt = FlutterBluetoothSerial.instance;
  BluetoothConnection? _connection;
  final _controller = StreamController<String>.broadcast();
  StreamSubscription<Uint8List>? _inputSub;
  final _lineBuffer = StringBuffer();

  Future<void> ensureOn() async {
    final state = await _bt.state;
    if (state != BluetoothState.STATE_ON) {
      await _bt.requestEnable();
    }
  }

  Future<List<BluetoothDiscoveryResult>> discover({Duration timeout = const Duration(seconds: 8)}) async {
    await ensureOn();
    final results = <BluetoothDiscoveryResult>[];
    final stream = _bt.startDiscovery();
    final c = Completer<void>();
    final sub = stream.listen(results.add, onDone: () => c.complete());
    await Future.any([Future.delayed(timeout), c.future]);
    await sub.cancel();
    await _bt.cancelDiscovery();
    final map = <String, BluetoothDiscoveryResult>{};
    for (final r in results) { map[r.device.address] = r; }
    return map.values.toList();
  }

  Future<List<BluetoothDevice>> bonded() async {
    await ensureOn();
    return _bt.getBondedDevices();
  }

  Future<void> connect(String address) async {
    await ensureOn();
    await disconnect();
    final conn = await BluetoothConnection.toAddress(address);
    _connection = conn;

    _inputSub = conn.input?.listen((Uint8List data) {
      final chunk = utf8.decode(data, allowMalformed: true);
      _lineBuffer.write(chunk);
      final parts = _lineBuffer.toString().split(RegExp(r'\r?\n'));
      for (int i = 0; i < parts.length - 1; i++) {
        final line = parts[i].trim();
        if (line.isNotEmpty) _controller.add(line);
      }
      _lineBuffer
        ..clear()
        ..write(parts.last);
    }, onDone: () => _controller.add('__DISCONNECTED__'),
       onError: (e) => _controller.add('__ERROR__: $e'));
  }

  Future<void> disconnect() async {
    await _inputSub?.cancel();
    _inputSub = null;
    await _connection?.finish();
    _connection = null;
  }

  Future<void> writeLine(String line) async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      throw StateError('No conectado');
    }
    conn.output.add(utf8.encode('$line\r\n'));
    await conn.output.allSent;
  }

  Stream<String> get lines => _controller.stream;
  Future<bool> isConnected() async => _connection?.isConnected == true;
}

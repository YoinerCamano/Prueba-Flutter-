import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BleDataSource {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Map<String, StreamSubscription<ConnectionStateUpdate>> _connections = {};
  StreamSubscription<DiscoveredDevice>? _scanSub;

  Stream<DiscoveredDevice> scanRaw() {
    _scanSub?.cancel();
    final controller = StreamController<DiscoveredDevice>();

    _scanSub = _ble.scanForDevices(withServices: []).listen(
      (d) {
        controller.add(d);
      },
      onError: (e, st) {
        controller.addError(e, st);
      },
      onDone: () {
        controller.close();
      },
      cancelOnError: false,
    );

    controller.onCancel = () {
      _scanSub?.cancel();
      _scanSub = null;
    };

    return controller.stream;
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
  }

  Stream<ConnectionStateUpdate> connectToDevice(String id) {
    // Conecta sin especificar servicio/characteristic (se negocia luego si necesitas).
    // Mantiene la conexión viva.
    return _ble.connectToDevice(id: id, connectionTimeout: const Duration(seconds: 15));
  }

  Future<void> disconnect(String id) async {
    await _connections[id]?.cancel();
    _connections.remove(id);
  }
}
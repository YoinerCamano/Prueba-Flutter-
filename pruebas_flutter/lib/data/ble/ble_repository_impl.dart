import 'dart:async';
import 'package:pruebas_flutter/data/ble/ble_datasource.dart';
import 'package:pruebas_flutter/domain/entities/ble_device.dart';
import 'package:pruebas_flutter/domain/repositories/ble_repository.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BleRepositoryImpl implements BleRepository {
  final BleDataSource dataSource;
  final Map<String, StreamController<bool>> _connControllers = {};
  StreamSubscription<DiscoveredDevice>? _scanListen;

  BleRepositoryImpl({required this.dataSource});

  @override
  Stream<List<BleDevice>> scan() {
    final devices = <String, BleDevice>{};
    _scanListen?.cancel();
    final controller = StreamController<List<BleDevice>>();

    _scanListen = dataSource.scanRaw().listen((d) {
      final id = d.id;
      final name = (d.name.isNotEmpty) ? d.name : 'Dispositivo sin nombre';
      devices[id] = BleDevice(id: id, name: name, rssi: d.rssi);
      controller.add(devices.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi)));
    }, onError: (e, st) {
      controller.addError(e, st);
    }, onDone: () {
      controller.close();
    });

    controller.onCancel = () async {
      await _scanListen?.cancel();
      _scanListen = null;
    };

    return controller.stream;
  }

  @override
  Future<void> stopScan() => dataSource.stopScan();

  @override
  Future<void> connect(String deviceId) async {
    final connCtrl = _connControllers.putIfAbsent(deviceId, () => StreamController<bool>.broadcast());

    await for (final update in dataSource.connectToDevice(deviceId)) {
      switch (update.connectionState) {
        case DeviceConnectionState.connected:
          connCtrl.add(true);
          break;
        case DeviceConnectionState.disconnected:
          connCtrl.add(false);
          return;
        case DeviceConnectionState.connecting:
        case DeviceConnectionState.disconnecting:
          // estados transitorios, no emitimos booleano
          break;
      }
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await dataSource.disconnect(deviceId);
    _connControllers[deviceId]?.add(false);
  }

  @override
  Stream<bool> connectionState(String deviceId) {
    final ctrl = _connControllers.putIfAbsent(deviceId, () => StreamController<bool>.broadcast());
    return ctrl.stream;
  }
}
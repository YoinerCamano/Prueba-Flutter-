import 'dart:async';
import 'dart:convert';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BleUartConfig {
  final Uuid serviceUuid;
  final Uuid txCharacteristic; // móvil -> dispositivo
  final Uuid rxCharacteristic; // dispositivo -> móvil (notify)
  const BleUartConfig({
    required this.serviceUuid,
    required this.txCharacteristic,
    required this.rxCharacteristic,
  });

  /// Nordic UART (NUS) por defecto
  factory BleUartConfig.nordic() => BleUartConfig(
        serviceUuid: Uuid.parse('6E400001-B5A3-F393-E0A9-E50E24DCCA9E'),
        txCharacteristic: Uuid.parse('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'),
        rxCharacteristic: Uuid.parse('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'),
      );
}

class BleAdapter {
  final _ble = FlutterReactiveBle();
  final BleUartConfig config;
  final _controller = StreamController<String>.broadcast();
  StreamSubscription<List<int>>? _notifySub;
  String? _deviceId;
  QualifiedCharacteristic? _rxQ;
  QualifiedCharacteristic? _txQ;

  BleAdapter({BleUartConfig? config}) : config = config ?? BleUartConfig.nordic();

  Future<List<DiscoveredDevice>> scan({Duration timeout = const Duration(seconds: 8)}) async {
    final devices = <String, DiscoveredDevice>{};
    final c = Completer<void>();
    final sub = _ble
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen((d) => devices[d.id] = d, onDone: () => c.complete(), onError: (_) {});
    await Future.any([Future.delayed(timeout), c.future]);
    await sub.cancel();
    return devices.values.toList();
  }

  Future<void> connect(String deviceId) async {
    await disconnect();

    await for (final update in _ble.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 10),
    )) {
      if (update.connectionState == DeviceConnectionState.connected) {
        _deviceId = deviceId;

        // Descubrir servicios y validar que está el UART requerido
        final services = await _ble.discoverServices(deviceId);

        // Buscar el servicio por UUID sin crear placeholders
        final matching = services.where((s) => s.serviceId == config.serviceUuid).toList();
        if (matching.isEmpty) {
          throw StateError('Servicio UART no encontrado');
        }
        // Si necesitas inspeccionar characteristics, están en matching.first.characteristics

        // Preparar características RX/TX
        _rxQ = QualifiedCharacteristic(
          deviceId: deviceId,
          serviceId: config.serviceUuid,
          characteristicId: config.rxCharacteristic,
        );
        _txQ = QualifiedCharacteristic(
          deviceId: deviceId,
          serviceId: config.serviceUuid,
          characteristicId: config.txCharacteristic,
        );

        // Suscribirse a notificaciones (RX)
        _notifySub = _ble.subscribeToCharacteristic(_rxQ!).listen((data) {
          final text = utf8.decode(data, allowMalformed: true);
          for (final part in text.split(RegExp(r'\r?\n'))) {
            final t = part.trim();
            if (t.isNotEmpty) _controller.add(t);
          }
        }, onError: (e) {
          _controller.add('__ERROR__: $e');
        }, onDone: () {
          _controller.add('__DISCONNECTED__');
        });

        return; // conexión BLE lista
      }

      if (update.connectionState == DeviceConnectionState.disconnected) {
        _controller.add('__DISCONNECTED__');
      }
    }
  }

  Future<void> writeLine(String line) async {
    final tx = _txQ;
    if (tx == null) {
      throw StateError('No conectado (BLE)');
    }
    final data = utf8.encode('$line\r\n');
    await _ble.writeCharacteristicWithoutResponse(tx, value: data);
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    _rxQ = null;
    _txQ = null;
    _deviceId = null;
  }

  Stream<String> get lines => _controller.stream;
  Future<bool> isConnected() async => _deviceId != null;
}


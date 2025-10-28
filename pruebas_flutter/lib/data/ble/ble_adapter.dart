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

  /// Configuración para Tru-Test S3 (puede usar servicio estándar)
  factory BleUartConfig.truTest() => BleUartConfig(
        serviceUuid: Uuid.parse('0000FFE0-0000-1000-8000-00805F9B34FB'),
        txCharacteristic: Uuid.parse('0000FFE1-0000-1000-8000-00805F9B34FB'),
        rxCharacteristic: Uuid.parse('0000FFE1-0000-1000-8000-00805F9B34FB'),
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

  BleAdapter({BleUartConfig? config})
      : config = config ?? BleUartConfig.nordic();

  Future<List<DiscoveredDevice>> scan(
      {Duration timeout = const Duration(seconds: 8)}) async {
    final devices = <String, DiscoveredDevice>{};
    final c = Completer<void>();
    final sub = _ble
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency).listen(
            (d) => devices[d.id] = d,
            onDone: () => c.complete(),
            onError: (_) {});
    await Future.any([Future.delayed(timeout), c.future]);
    await sub.cancel();
    return devices.values.toList();
  }

  Future<void> connect(String deviceId) async {
    print('🔗 Conectando a dispositivo BLE: $deviceId');
    await disconnect();

    await for (final update in _ble.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 10),
    )) {
      if (update.connectionState == DeviceConnectionState.connected) {
        print('✅ Dispositivo BLE conectado');
        _deviceId = deviceId;

        // Descubrir servicios disponibles
        print('🔍 Descubriendo servicios...');
        final services = await _ble.discoverServices(deviceId);
        print('📡 Servicios encontrados: ${services.length}');

        // Mostrar todos los servicios para debugging
        for (int i = 0; i < services.length; i++) {
          final service = services[i];
          print('🔹 Servicio $i: ${service.serviceId}');
          for (int j = 0; j < service.characteristics.length; j++) {
            final char = service.characteristics[j];
            print('   📍 Característica $j: ${char.characteristicId}');
            print(
                '     🔧 Readable: ${char.isReadable}, Writable: ${char.isWritableWithoutResponse}');
          }
        }

        // Buscar servicios UART conocidos (múltiples configuraciones)
        final uartConfigs = [
          // Configuración Tru-Test
          BleUartConfig.truTest(),
          // Configuración Nordic estándar
          BleUartConfig.nordic(),
          // Configuración genérica
          BleUartConfig(
            serviceUuid: Uuid.parse('0000180A-0000-1000-8000-00805F9B34FB'),
            txCharacteristic:
                Uuid.parse('00002A29-0000-1000-8000-00805F9B34FB'),
            rxCharacteristic:
                Uuid.parse('00002A29-0000-1000-8000-00805F9B34FB'),
          ),
        ];

        BleUartConfig? workingConfig;
        DiscoveredService? workingService;

        // Probar cada configuración
        for (final testConfig in uartConfigs) {
          print('🧪 Probando configuración: ${testConfig.serviceUuid}');
          final matching = services
              .where((s) => s.serviceId == testConfig.serviceUuid)
              .toList();
          if (matching.isNotEmpty) {
            print('✅ Servicio encontrado: ${testConfig.serviceUuid}');
            workingConfig = testConfig;
            workingService = matching.first;
            break;
          } else {
            print('❌ Servicio no encontrado: ${testConfig.serviceUuid}');
          }
        }

        // Si no encontramos servicios conocidos, intentar con el primer servicio disponible
        if (workingConfig == null && services.isNotEmpty) {
          print('🔄 Intentando con el primer servicio disponible...');
          final firstService = services.first;
          if (firstService.characteristics.isNotEmpty) {
            final firstChar = firstService.characteristics.first;
            print('🎯 Usando servicio genérico: ${firstService.serviceId}');
            print('🎯 Usando característica: ${firstChar.characteristicId}');

            workingConfig = BleUartConfig(
              serviceUuid: firstService.serviceId,
              txCharacteristic: firstChar.characteristicId,
              rxCharacteristic: firstChar.characteristicId,
            );
            workingService = firstService;
          }
        }

        if (workingConfig == null) {
          print('❌ No se encontró ningún servicio UART compatible');
          throw StateError(
              'No se encontró servicio UART compatible en el dispositivo');
        }

        print('🎉 Usando configuración: ${workingConfig.serviceUuid}');

        // Preparar características RX/TX
        _rxQ = QualifiedCharacteristic(
          deviceId: deviceId,
          serviceId: workingConfig.serviceUuid,
          characteristicId: workingConfig.rxCharacteristic,
        );
        _txQ = QualifiedCharacteristic(
          deviceId: deviceId,
          serviceId: workingConfig.serviceUuid,
          characteristicId: workingConfig.txCharacteristic,
        );

        // Verificar propiedades de la característica
        final rxChar = workingService!.characteristics
            .where((c) => c.characteristicId == workingConfig!.rxCharacteristic)
            .firstOrNull;

        if (rxChar != null) {
          print('📡 Característica RX encontrada: ${rxChar.characteristicId}');
          print(
              '📡 Readable: ${rxChar.isReadable}, Notifiable: ${rxChar.isNotifiable}');

          // Suscribirse a notificaciones solo si la característica lo soporta
          if (rxChar.isNotifiable) {
            print('🔔 Suscribiéndose a notificaciones...');
            _notifySub = _ble.subscribeToCharacteristic(_rxQ!).listen((data) {
              final text = utf8.decode(data, allowMalformed: true);
              print('📨 Datos recibidos: $text');
              for (final part in text.split(RegExp(r'\r?\n'))) {
                final t = part.trim();
                if (t.isNotEmpty) _controller.add(t);
              }
            }, onError: (e) {
              print('❌ Error en notificaciones: $e');
              _controller.add('__ERROR__: $e');
            }, onDone: () {
              print('🔌 Notificaciones terminadas');
              _controller.add('__DISCONNECTED__');
            });
            print('✅ Suscripción a notificaciones establecida');
          } else {
            print('⚠️ La característica no soporta notificaciones');
          }
        }
        print('🎉 Conexión BLE completamente establecida');
        return; // conexión BLE lista
      }

      if (update.connectionState == DeviceConnectionState.disconnected) {
        print('🔌 Dispositivo BLE desconectado');
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

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
      {Duration timeout = const Duration(seconds: 15)}) async {
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
      connectionTimeout: const Duration(seconds: 20),
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
              '📡 Readable: ${rxChar.isReadable}, Notifiable: ${rxChar.isNotifiable}, Indicatable: ${rxChar.isIndicatable}');

          // Suscribirse a notificaciones solo si la característica lo soporta
          if (rxChar.isNotifiable || rxChar.isIndicatable) {
            print('🔔 Suscribiéndose a notificaciones...');

            // NUEVO: Verificar si necesitamos habilitar notificaciones manualmente
            print('🔧 Intentando habilitar notificaciones en el descriptor...');

            try {
              // Habilitar notificaciones escribiendo en el descriptor CCCD
              final cccdDescriptor = QualifiedCharacteristic(
                deviceId: deviceId,
                serviceId: workingConfig.serviceUuid,
                characteristicId: workingConfig.rxCharacteristic,
              );

              // Valor para habilitar notificaciones: [0x01, 0x00]
              // Valor para habilitar indicaciones: [0x02, 0x00]
              List<int> enableValue;
              if (rxChar.isNotifiable) {
                enableValue = [0x01, 0x00]; // Notificaciones
                print('📡 Habilitando NOTIFICACIONES...');
              } else {
                enableValue = [0x02, 0x00]; // Indicaciones
                print('📡 Habilitando INDICACIONES...');
              }

              // Escribir el valor en el descriptor (esto puede fallar en algunos dispositivos)
              try {
                await _ble.writeCharacteristicWithResponse(cccdDescriptor,
                    value: enableValue);
                print('✅ Descriptor CCCD habilitado exitosamente');
              } catch (e) {
                print(
                    '⚠️ No se pudo escribir descriptor CCCD (normal en algunos dispositivos): $e');
              }
            } catch (e) {
              print('⚠️ Error configurando descriptores: $e');
            }

            // Intentar habilitar notificaciones explícitamente
            try {
              await _ble.requestMtu(deviceId: deviceId, mtu: 512);
              print('📡 MTU configurado a 512 bytes');
            } catch (e) {
              print('⚠️ No se pudo configurar MTU: $e');
            }
            _notifySub = _ble.subscribeToCharacteristic(_rxQ!).listen((data) {
              // === LOGGING DETALLADO DE DATOS RAW BLE ===
              print('');
              print(
                  '🔄 =============== DATOS RAW BLE RECIBIDOS ===============');

              final hexData = data
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join(' ');
              print('📨 Datos RAW (HEX): $hexData');
              print('📨 Datos RAW (DEC): ${data.join(', ')}');
              print('📨 Cantidad de bytes: ${data.length}');

              // Mostrar cada byte individualmente
              for (int i = 0; i < data.length; i++) {
                final byte = data[i];
                final char = (byte >= 32 && byte <= 126)
                    ? String.fromCharCode(byte)
                    : '?';
                print(
                    '📨 Byte[$i]: $byte (0x${byte.toRadixString(16).padLeft(2, '0')}) = "$char"');
              }

              // Intentar decodificar como texto
              try {
                final text = utf8.decode(data, allowMalformed: true);
                print('📨 Texto UTF-8 decodificado: "$text"');
                print('📨 Longitud del texto: ${text.length} caracteres');

                // Analizar el contenido del texto
                if (text.contains('\r')) print('📨 Contiene CR (\\r)');
                if (text.contains('\n')) print('📨 Contiene LF (\\n)');
                if (text.contains('\t')) print('📨 Contiene TAB (\\t)');
                if (text.contains(' ')) print('📨 Contiene espacios');

                print(
                    '========================================================');
                print('');

                if (text.isNotEmpty) {
                  // Procesar respuestas sin dividir por líneas primero
                  print('📤 Enviando al stream: "$text"');
                  _controller.add(text);

                  // También procesar por líneas si hay saltos
                  for (final part in text.split(RegExp(r'\r?\n'))) {
                    final t = part.trim();
                    if (t.isNotEmpty && t != text) {
                      print('📤 Enviando línea adicional: "$t"');
                      _controller.add(t);
                    }
                  }
                }
              } catch (e) {
                print('❌ Error decodificando UTF-8: $e');
                // Si no se puede decodificar como UTF-8, enviar como datos hex
                _controller.add('HEX: $hexData');
              }
            }, onError: (e) {
              print('❌ Error en notificaciones: $e');
              print('🔄 Intentando reconectar notificaciones...');
              // No cerrar el stream en caso de error, intentar mantener conexión
              _controller.add('__ERROR__: $e');

              // Intentar reestablecer notificaciones después de un delay
              Future.delayed(const Duration(seconds: 5), () {
                _attemptNotificationReconnect();
              });
            }, onDone: () {
              print(
                  '🔌 Notificaciones terminadas - Stream cerrado por dispositivo');
              print('🔄 Intentando reestablecer notificaciones...');

              // Intentar reestablecer notificaciones automáticamente
              Future.delayed(const Duration(seconds: 1), () {
                _attemptNotificationReconnect();
              });
            });
            print('✅ Suscripción a notificaciones establecida');

            // Enviar comando de prueba para verificar comunicación
            print(
                '🧪 Enviando comando de prueba para verificar comunicación...');
            print('⏱️ Esperando 2 segundos para estabilizar notificaciones...');
            await Future.delayed(const Duration(seconds: 2));

            try {
              final testData = utf8.encode('{RW}\r\n');
              await _ble.writeCharacteristicWithoutResponse(_txQ!,
                  value: testData);
              print(
                  '🧪 Comando de prueba enviado: {RW} con CR+LF (sin respuesta)');

              // Esperar un poco después del comando para ver si llegan datos
              print('⏱️ Esperando respuesta por 3 segundos...');
              await Future.delayed(const Duration(seconds: 3));
              print('🧪 Finalizada espera de comando de prueba');
            } catch (e) {
              print('❌ Error enviando comando de prueba: $e');
            }
          } else {
            print(
                '⚠️ La característica RX no soporta notificaciones o indicaciones');
          }
        }

        // Verificar también la característica TX
        final txChar = workingService.characteristics
            .where((c) => c.characteristicId == workingConfig!.txCharacteristic)
            .firstOrNull;

        if (txChar != null) {
          print('📡 Característica TX encontrada: ${txChar.characteristicId}');
          print(
              '📡 Writable: ${txChar.isWritableWithResponse}, WritableWithoutResponse: ${txChar.isWritableWithoutResponse}');
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

    // === LOGGING DETALLADO DE ENVÍO DE COMANDOS ===
    print('');
    print('🔄 =============== ENVIANDO COMANDO A BÁSCULA ===============');
    print('📤 Comando original: "$line"');
    print('📤 Longitud comando: ${line.length} caracteres');

    // Probar diferentes formatos basados en la configuración de la terminal serial
    List<int> data;

    // NUEVO: Basado en terminal serial que usa CR+LF para comandos Tru-Test S3
    if (line.startsWith('{') && line.endsWith('}')) {
      // Probar con CR+LF como sugiere la configuración de la terminal
      data = utf8.encode('$line\r\n');
      print('📤 Formato: Comando con CR+LF (basado en terminal serial)');
    } else {
      // Para otros comandos, usar formato estándar con CRLF
      data = utf8.encode('$line\r\n');
      print('📤 Formato: Comando con CRLF');
    }

    print('📤 Bytes a enviar: ${data.length}');
    print(
        '📤 Datos (HEX): ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    print('📤 Datos (DEC): ${data.join(', ')}');

    // Mostrar cada byte individualmente
    for (int i = 0; i < data.length; i++) {
      final byte = data[i];
      final char =
          (byte >= 32 && byte <= 126) ? String.fromCharCode(byte) : '?';
      print(
          '📤 Byte[$i]: $byte (0x${byte.toRadixString(16).padLeft(2, '0')}) = "$char"');
    }
    print('========================================================');
    print('');

    print(
        '📡 Datos enviados: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    await _ble.writeCharacteristicWithoutResponse(tx, value: data);
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    _rxQ = null;
    _txQ = null;
    _deviceId = null;
  }

  // Método para intentar reestablecer notificaciones
  Future<void> _attemptNotificationReconnect() async {
    if (_rxQ == null || _deviceId == null) {
      print(
          '⚠️ No se puede reconectar notificaciones: _rxQ o _deviceId es null');
      return;
    }

    try {
      print('🔄 Reestableciendo suscripción a notificaciones...');

      // Cancelar suscripción anterior si existe
      await _notifySub?.cancel();

      // Esperar un poco antes de reintentarlo
      await Future.delayed(const Duration(milliseconds: 500));

      // Reestablecer suscripción
      _notifySub = _ble.subscribeToCharacteristic(_rxQ!).listen((data) {
        // Reutilizar el mismo código de procesamiento de datos
        print('');
        print(
            '🔄 =============== DATOS RAW BLE RECIBIDOS (RECONECTADO) ===============');

        final hexData =
            data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        print('📨 Datos RAW (HEX): $hexData');
        print('📨 Datos RAW (DEC): ${data.join(', ')}');
        print('📨 Cantidad de bytes: ${data.length}');

        try {
          final text = utf8.decode(data, allowMalformed: true);
          print('📨 Texto UTF-8 decodificado: "$text"');
          print('📨 Longitud del texto: ${text.length} caracteres');
          print('========================================================');
          print('');

          if (text.isNotEmpty) {
            print('📤 Enviando al stream: "$text"');
            _controller.add(text);

            for (final part in text.split(RegExp(r'\r?\n'))) {
              final t = part.trim();
              if (t.isNotEmpty && t != text) {
                print('📤 Enviando línea adicional: "$t"');
                _controller.add(t);
              }
            }
          }
        } catch (e) {
          print('❌ Error decodificando UTF-8: $e');
          _controller.add('HEX: $hexData');
        }
      }, onError: (e) {
        print('❌ Error en notificaciones reconectadas: $e');
        _controller.add('__ERROR__: $e');
      }, onDone: () {
        print('🔌 Notificaciones reconectadas terminadas');
        _controller.add('__DISCONNECTED__');
      });

      print('✅ Notificaciones reestablecidas exitosamente');
    } catch (e) {
      print('❌ Error reestableciendo notificaciones: $e');
    }
  }

  Stream<String> get lines => _controller.stream;
  Future<bool> isConnected() async => _deviceId != null;
}

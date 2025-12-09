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

  /// Lista dispositivos emparejados con logs detallados
  Future<List<BluetoothDevice>> bonded() async {
    print('🔍 === OBTENIENDO DISPOSITIVOS EMPAREJADOS ===');
    await ensureOn();

    final devices = await _bt.getBondedDevices();
    print('📋 Total dispositivos emparejados encontrados: ${devices.length}');

    if (devices.isEmpty) {
      print('❌ NO HAY DISPOSITIVOS EMPAREJADOS');
      print('💡 Solución: Emparejar la S3 desde Configuración de Android');
      return devices;
    }

    // Mostrar todos los dispositivos para debugging
    for (int i = 0; i < devices.length; i++) {
      final device = devices[i];
      final name = device.name ?? 'Sin nombre';
      final address = device.address;

      print('📱 [$i] $name ($address)');

      // Verificar si es la S3 específicamente
      if (address == 'DE:FD:76:A4:D7:ED') {
        print('⚖️  *** BÁSCULA S3 ENCONTRADA POR MAC ***');
        print('✅ Nombre: $name');
        print('✅ Estado: Emparejada');
      } else if (name.contains('S3') || name.contains('680066')) {
        print('⚖️  *** POSIBLE S3 ENCONTRADA POR NOMBRE ***');
        print('🔍 Verificar si es la báscula correcta');
      }
    }

    return devices;
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
    print('');
    print('🔗 === CONEXIÓN ESPECÍFICA PARA TRU-TEST S3 ===');
    print('🎯 Dirección objetivo: $address');
    print('⏰ Inicio: ${DateTime.now()}');

    try {
      await ensureOn();

      // Limpieza específica para S3
      print('🧹 Desconectando conexiones previas...');
      await disconnect();

      print('🔍 Cancelando discovery múltiples veces...');
      for (int i = 0; i < 3; i++) {
        try {
          await _bt.cancelDiscovery();
          await Future.delayed(const Duration(milliseconds: 300));
          print('  Discovery cancelado ${i + 1}/3');
        } catch (e) {
          print('  Error cancelando discovery ${i + 1}: $e');
        }
      }

      // ESTRATEGIA MÚLTIPLE DE CONEXIÓN
      BluetoothConnection? conn;
      Exception? lastError;

      // INTENTO 1: Conexión directa rápida
      print('');
      print('🚀 === INTENTO 1: CONEXIÓN DIRECTA ===');
      try {
        print('⏳ Pausa corta (1 segundo)...');
        await Future.delayed(const Duration(milliseconds: 1000));

        print('� Intentando conexión directa...');
        conn = await BluetoothConnection.toAddress(address).timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw TimeoutException(
              'Timeout en conexión directa', const Duration(seconds: 8)),
        );

        if (conn.isConnected) {
          print('✅ INTENTO 1 EXITOSO: Conexión directa establecida');
        } else {
          throw Exception('Socket creado pero no conectado');
        }
      } catch (e) {
        print('❌ INTENTO 1 FALLÓ: $e');
        lastError = e is Exception ? e : Exception(e.toString());
        await conn?.finish();
        conn = null;
      }

      // INTENTO 2: Conexión con pausa larga
      if (conn == null) {
        print('');
        print('� === INTENTO 2: CONEXIÓN CON PAUSA LARGA ===');
        try {
          print('⏳ Pausa larga para estabilización (8 segundos)...');
          await Future.delayed(const Duration(milliseconds: 8000));

          print('🔄 Intentando conexión con timeout extendido...');
          conn = await BluetoothConnection.toAddress(address).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
                'Timeout en conexión extendida', const Duration(seconds: 15)),
          );

          if (conn.isConnected) {
            print('✅ INTENTO 2 EXITOSO: Conexión con pausa larga establecida');
          } else {
            throw Exception('Socket creado pero no conectado en intento 2');
          }
        } catch (e) {
          print('❌ INTENTO 2 FALLÓ: $e');
          lastError = e is Exception ? e : Exception(e.toString());
          await conn?.finish();
          conn = null;
        }
      }

      // INTENTO 3: Reconexión con reset de adaptador
      if (conn == null) {
        print('');
        print('🚀 === INTENTO 3: RECONEXIÓN CON RESET ===');
        try {
          print('🔄 Deshabilitando Bluetooth temporalmente...');
          try {
            await _bt.requestDisable();
            await Future.delayed(const Duration(milliseconds: 3000));
          } catch (e) {
            print('⚠️ No se pudo deshabilitar BT: $e');
          }

          print('🔄 Reactivando Bluetooth...');
          await ensureOn();
          await Future.delayed(const Duration(milliseconds: 5000));

          print('� Intentando conexión después del reset...');
          conn = await BluetoothConnection.toAddress(address).timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw TimeoutException(
                'Timeout después del reset', const Duration(seconds: 12)),
          );

          if (conn.isConnected) {
            print(
                '✅ INTENTO 3 EXITOSO: Conexión después del reset establecida');
          } else {
            throw Exception('Socket creado pero no conectado en intento 3');
          }
        } catch (e) {
          print('❌ INTENTO 3 FALLÓ: $e');
          lastError = e is Exception ? e : Exception(e.toString());
          await conn?.finish();
          conn = null;
        }
      }

      // Verificar si algún intento fue exitoso
      if (conn == null) {
        print('');
        print('❌ *** TODOS LOS INTENTOS FALLARON ***');
        throw Exception('No se pudo conectar después de 3 intentos.\n\n'
            'Último error: $lastError\n\n'
            'Soluciones:\n'
            '1. Reinicia la báscula S3 (apagar/encender)\n'
            '2. Ve a Configuración > Bluetooth > S3 > Olvidar dispositivo\n'
            '3. Vuelve a emparejar la S3\n'
            '4. Asegúrate de que la S3 no esté conectada a otro dispositivo\n'
            '5. Mantén la S3 cerca del celular (< 1 metro)');
      }

      _connection = conn;

      // Configurar escucha con parámetros específicos para S3
      print('🎧 Configurando listener de datos S3...');
      _inputSub = conn.input?.listen(
        (Uint8List data) {
          final chunk = utf8.decode(data, allowMalformed: true);
          print(
              '📥 Raw data S3: "${chunk.replaceAll('\r', '\\r').replaceAll('\n', '\\n')}"');

          _lineBuffer.write(chunk);
          final bufferContent = _lineBuffer.toString();

          // Si hay saltos de línea, procesar por líneas completas
          if (bufferContent.contains('\n') || bufferContent.contains('\r')) {
            final parts = bufferContent.split(RegExp(r'\r?\n'));

            for (int i = 0; i < parts.length - 1; i++) {
              final line = parts[i].trim();
              if (line.isNotEmpty) {
                print('📊 Línea S3 completa: "$line"');
                _controller.add(line);
              }
            }

            _lineBuffer
              ..clear()
              ..write(parts.last);
          } else {
            // Sin saltos de línea: emitir fragmentos directamente (EziWeigh7)
            // Solo si hay contenido que no sea solo espacios
            final trimmed = bufferContent.trim();
            if (trimmed.isNotEmpty) {
              print('📦 Fragmento directo: "$trimmed"');
              _controller.add(trimmed);
              _lineBuffer.clear();
            }
          }
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

      // Inicialización específica para S3 (no para EziWeigh7)
      // La EziWeigh7 no necesita wake-up, responde inmediatamente
      final needsWakeup = true; // TODO: Detectar modelo y condicionar

      if (needsWakeup) {
        print('⏳ Pausa antes del wake-up (2 segundos)...');
        await Future.delayed(const Duration(milliseconds: 2000));
        try {
          print('📤 Enviando comando wake-up a S3...');
          conn.output.add(utf8.encode('\r\n'));
          await conn.output.allSent;
          print('✅ Wake-up enviado');
        } catch (e) {
          print('⚠️ Advertencia comando wake-up: $e');
        }
      } else {
        print('ℹ️ EziWeigh7 detectada, omitiendo wake-up');
      }

      print('');
      print('🎉 *** CONEXIÓN S3 COMPLETADA EXITOSAMENTE ***');
      print('⚖️ La báscula Tru-Test S3 está lista para recibir comandos');
      print('⏰ Finalizada: ${DateTime.now()}');
      print('');
    } catch (e) {
      print('');
      print('❌ *** ERROR CONECTANDO A S3 ***');
      print('💥 Error: $e');
      print('⏰ Error en: ${DateTime.now()}');
      print('');

      throw Exception('Error conectando a Tru-Test S3: $e\n\n'
          'Soluciones:\n'
          '1. Apague y encienda la báscula\n'
          '2. Mantenga la báscula cerca del dispositivo\n'
          '3. Verifique que no hay interferencias\n'
          '4. Desemparejar y volver a emparejar el dispositivo');
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
      print('❌ Error: No hay conexión activa con S3');
      throw StateError('No conectado a S3');
    }

    print('📤 Enviando comando a S3: "$line"');
    try {
      conn.output.add(utf8.encode('$line\r\n'));
      await conn.output.allSent;
      print('✅ Comando enviado exitosamente');
    } catch (e) {
      print('❌ Error enviando comando: $e');
      throw StateError('Error enviando comando a S3: $e');
    }
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
    print('🔍 === ESCANEO BLUETOOTH CLÁSICO ===');
    print('⏱️ Timeout: ${timeout.inSeconds} segundos');

    try {
      await adapter.ensureOn();

      // Verificar estado inicial de discovery
      print('🔍 Verificando estado de discovery...');
      try {
        final isDiscovering = await adapter._bt.isDiscovering;
        print('Discovery activo: $isDiscovering');
        if (isDiscovering == true) {
          print('⏹️ Cancelando discovery previo...');
          await adapter._bt.cancelDiscovery();
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      } catch (e) {
        print('Error verificando discovery: $e');
      }

      // Intentar discovery real por un tiempo limitado
      print('🚀 Iniciando discovery...');
      try {
        final started = await adapter._bt.startDiscovery();
        print('Discovery iniciado: $started');

        if (started == true) {
          final discoveryTime = Duration(
              seconds: (timeout.inSeconds * 0.6)
                  .round()); // 60% del tiempo para discovery
          print('⏳ Escaneando por ${discoveryTime.inSeconds} segundos...');
          await Future.delayed(discoveryTime);

          print('⏹️ Deteniendo discovery...');
          await adapter._bt.cancelDiscovery();
          print('✅ Discovery detenido');
        } else {
          print('❌ No se pudo iniciar discovery');
        }
      } catch (e) {
        print('❌ Error en discovery: $e');
      }
    } catch (e) {
      print('❌ Error general en escaneo: $e');
    }

    // Obtener todos los dispositivos emparejados (discovery puede encontrar más)
    final bonded = await adapter.bonded();
    print('📋 Total dispositivos emparejados: ${bonded.length}');

    for (final device in bonded) {
      print(
          '📱 Dispositivo: ${device.name ?? 'Sin nombre'} (${device.address})');
    }

    // Filtrar específicamente para S3 si está disponible
    final s3Devices = bonded
        .where((d) =>
            d.address == 'DE:FD:76:A4:D7:ED' ||
            (d.name?.contains('S3') == true) ||
            (d.name?.contains('680066') == true))
        .toList();

    if (s3Devices.isNotEmpty) {
      print('⚖️ Dispositivos S3 encontrados: ${s3Devices.length}');
      for (final device in s3Devices) {
        print('✅ S3: ${device.name} (${device.address})');
      }
    } else {
      print('⚠️ No se encontraron dispositivos S3 específicos');
      print(
          '💡 Verifique que la báscula esté emparejada en Configuración de Android');
    }

    // Retornar TODOS los dispositivos emparejados, no solo S3
    return bonded
        .map((d) => BtDevice(
            id: d.address,
            name: d.name?.isNotEmpty == true ? d.name! : d.address))
        .toList();
  }

  @override
  Future<List<BtDevice>> bondedDevices() async {
    print('📋 === REPOSITORIO: OBTENIENDO DISPOSITIVOS VINCULADOS ===');

    final devices = await adapter.bonded();
    print('🔗 Dispositivos obtenidos del adaptador: ${devices.length}');

    final btDevices = devices
        .map((d) => BtDevice(
            id: d.address,
            name: d.name?.isNotEmpty == true ? d.name! : d.address))
        .toList();

    print('📱 Dispositivos convertidos a BtDevice: ${btDevices.length}');
    for (int i = 0; i < btDevices.length; i++) {
      final device = btDevices[i];
      print('🔹 [$i] ${device.name} (${device.id})');

      // Verificar S3
      if (device.id == 'DE:FD:76:A4:D7:ED' ||
          device.name.contains('S3') ||
          device.name.contains('680066')) {
        print('⚖️  *** S3 ENCONTRADA EN REPOSITORIO ***');
      }
    }

    return btDevices;
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

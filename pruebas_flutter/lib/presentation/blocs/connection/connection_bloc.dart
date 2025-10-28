import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/number_parsing.dart';
import '../../../domain/bluetooth_repository.dart';
import '../../../domain/entities.dart';

part 'connection_event.dart';
part 'connection_state.dart';

class ConnectionBloc extends Bloc<ConnectionEvent, ConnectionState> {
  final BluetoothRepository repo;
  StreamSubscription<String>? _sub;
  Timer? _pollTimer;

  ConnectionBloc(this.repo) : super(const ConnectionState.disconnected()) {
    on<ConnectRequested>(_onConnect);
    on<DisconnectRequested>(_onDisconnect);
    on<RawLineArrived>(_onRawLine);
    on<SendCommandRequested>(_onSendCommand);
    on<StartPolling>(_onStartPolling);
    on<StopPolling>(_onStopPolling);
    on<CheckManualConnectionRequested>(_onCheckManualConnection);
  }

  Future<void> _onConnect(
      ConnectRequested e, Emitter<ConnectionState> emit) async {
    print('🔗 === INICIANDO PROCESO DE CONEXIÓN ===');
    print('🎯 Dispositivo objetivo: ${e.device.name} (${e.device.id})');

    emit(ConnectionState.connecting(device: e.device));
    await _sub?.cancel();
    _pollTimer?.cancel(); // Detener polling anterior

    try {
      print('📡 Intentando conectar via repositorio...');
      await repo.connect(e.device.id);

      // Verificar que realmente estamos conectados con timeout
      print('🔍 Verificando estado de conexión...');
      bool connected = false;

      // Intentar verificar conexión hasta 3 veces con delay
      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        connected = await repo.isConnected();
        print('📊 Verificación ${i + 1}/3: $connected');
        if (connected) break;
      }

      if (connected) {
        print('✅ Conexión verificada, configurando streams...');
        _sub = repo.rawStream().listen((line) {
          print('');
          print('🔄 =============== DATOS DEL STREAM ===============');
          print('📥 Datos recibidos del stream: "$line"');
          print('📥 Timestamp: ${DateTime.now().toIso8601String()}');
          print('================================================');
          print('');
          add(RawLineArrived(line));
        }, onError: (error) {
          print('❌ Error en stream: $error');
          add(RawLineArrived('__ERROR__: $error'));
        }, onDone: () {
          print('🔌 Stream terminado');
          add(RawLineArrived('__DISCONNECTED__'));
        });

        emit(ConnectionState.connected(device: e.device));

        // Esperar más tiempo antes de iniciar polling para S3
        print('⏳ Esperando estabilización antes de iniciar polling...');
        await Future.delayed(const Duration(milliseconds: 2000));
        add(StartPolling());

        print('🎉 *** CONEXIÓN COMPLETADA EXITOSAMENTE ***');
      } else {
        print('❌ La verificación de conexión falló');
        emit(ConnectionState.error(
            'La conexión no se estableció correctamente después de múltiples verificaciones'));
      }
    } catch (err) {
      // Asegurar que el polling esté detenido en caso de error
      _pollTimer?.cancel();
      _pollTimer = null;
      print('💥 Error en proceso de conexión: $err');
      emit(ConnectionState.error('Error al conectar: $err'));
    }
  }

  Future<void> _onDisconnect(
      DisconnectRequested e, Emitter<ConnectionState> emit) async {
    await _sub?.cancel();
    _sub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    await repo.disconnect();
    emit(const ConnectionState.disconnected());
  }

  void _onRawLine(RawLineArrived e, Emitter<ConnectionState> emit) {
    final s = state;
    if (s is! Connected) return;
    final line = e.line.trim();

    // === LOGGING DETALLADO DE TODOS LOS DATOS RECIBIDOS ===
    print('');
    print('🔄 =============== DATOS RECIBIDOS DE BÁSCULA ===============');
    print('📨 Línea completa: "$line"');
    print('📏 Longitud: ${line.length} caracteres');
    print(
        '🔤 Caracteres individuales: ${line.split('').map((c) => "'$c'").join(', ')}');
    print(
        '🔢 Códigos ASCII: ${line.runes.map((r) => r.toString()).join(', ')}');
    print(
        '🔠 Códigos HEX: ${line.runes.map((r) => '0x${r.toRadixString(16)}').join(', ')}');

    if (line.isNotEmpty) {
      print('🎯 Primer carácter: "${line[0]}" (ASCII: ${line.codeUnitAt(0)})');
      print(
          '🎯 Último carácter: "${line[line.length - 1]}" (ASCII: ${line.codeUnitAt(line.length - 1)})');
    }

    // Detectar posibles patrones comunes
    if (line.contains('|')) {
      print('📊 Contiene pipes (|) - posible formato delimitado');
      final parts = line.split('|');
      print(
          '📊 Partes separadas por |: ${parts.map((p) => '"$p"').join(', ')}');
    }

    if (line.contains(',')) {
      print('📊 Contiene comas (,) - posible formato CSV');
      final parts = line.split(',');
      print(
          '📊 Partes separadas por ,: ${parts.map((p) => '"$p"').join(', ')}');
    }

    if (line.contains(';')) {
      print('📊 Contiene punto y coma (;) - posible formato delimitado');
      final parts = line.split(';');
      print(
          '📊 Partes separadas por ;: ${parts.map((p) => '"$p"').join(', ')}');
    }

    if (RegExp(r'\d').hasMatch(line)) {
      print('🔢 Contiene números - posibles datos numéricos');
      final numbers =
          RegExp(r'\d+\.?\d*').allMatches(line).map((m) => m.group(0)).toList();
      print('🔢 Números encontrados: ${numbers.join(', ')}');
    }

    if (line.contains('{') || line.contains('}')) {
      print('🔧 Contiene llaves - posible comando o respuesta estructurada');
    }

    if (line.contains('[') || line.contains(']')) {
      print('🔧 Contiene corchetes - posible formato estructurado');
    }

    print('========================================================');
    print('');

    print('🔍 Procesando línea: "$line"');

    if (line == '__DISCONNECTED__') {
      print('🔌 Desconexión detectada');
      emit(const ConnectionState.disconnected());
      return;
    }

    // Detectar formato específico de Tru-Test S3: "88|7.95|3.308|1.02|09:31:44.340"
    // Formato: ID|PESO|VALOR1|VALOR2|TIMESTAMP
    final s3Regex = RegExp(r'^\d+\|(\d+\.?\d*)\|[\d\.]+\|[\d\.]+\|[\d:\.]+$');
    final s3Match = s3Regex.firstMatch(line);

    if (s3Match != null) {
      final weightStr = s3Match.group(1);
      final weight = double.tryParse(weightStr ?? '');
      if (weight != null) {
        print('⚖️  PESO S3 (formato pipes) DETECTADO: ${weight}kg');
        emit(s.copyWith(weight: WeightReading(kg: weight, at: DateTime.now())));
        return;
      }
    }

    // Detectar datos de peso específicos para Tru-Test S3 (formato original)
    // Formato esperado: [peso] ej: [0.00], [23.45], etc.
    final weightRegex = RegExp(r'\[(\d+\.?\d*)\]');
    final weightMatch = weightRegex.firstMatch(line);

    if (weightMatch != null) {
      final weightStr = weightMatch.group(1);
      final weight = double.tryParse(weightStr ?? '');
      if (weight != null) {
        print('⚖️  PESO S3 (formato corchetes) DETECTADO: ${weight}kg');
        emit(s.copyWith(weight: WeightReading(kg: weight, at: DateTime.now())));
        return;
      }
    }

    // Detectar datos de batería
    if (line.toUpperCase().contains('BV') || line.toUpperCase().contains('V')) {
      final v = extractFirstNumber(line);
      if (v != null) {
        print('🔋 BATERÍA VOLTAJE: ${v}V');
        emit(s.copyWith(battery: BatteryStatus(volts: v, at: DateTime.now())));
        return;
      }
    }

    if (line.toUpperCase().contains('BC') || line.contains('%')) {
      final p = extractFirstNumber(line);
      if (p != null) {
        print('🔋 BATERÍA PORCENTAJE: ${p}%');
        emit(
            s.copyWith(battery: BatteryStatus(percent: p, at: DateTime.now())));
        return;
      }
    }

    // Fallback: intentar extraer cualquier número como peso
    final kg = extractFirstNumber(line);
    if (kg != null) {
      print('📊 PESO GENÉRICO: ${kg}kg');
      emit(s.copyWith(weight: WeightReading(kg: kg, at: DateTime.now())));
    } else {
      print('❓ Línea no reconocida: "$line"');
      print(
          '🔍 Caracteres hex de la línea: ${line.runes.map((r) => r.toRadixString(16)).join(' ')}');
    }
  }

  Future<void> _onSendCommand(
      SendCommandRequested e, Emitter<ConnectionState> emit) async {
    try {
      // Verificar si realmente estamos conectados antes de enviar
      if (!await repo.isConnected()) {
        print(
            '⚠️  Intento de enviar comando sin conexión activa, deteniendo polling');
        _pollTimer?.cancel();
        _pollTimer = null;
        emit(const ConnectionState.disconnected());
        return;
      }

      print('📤 Enviando comando: ${e.command}');
      await repo.sendCommand(e.command);
      print('✅ Comando enviado exitosamente');
    } catch (err) {
      print('❌ Error enviando comando ${e.command}: $err');

      // Analizar el tipo de error para decidir la acción
      final errorMsg = err.toString().toLowerCase();

      if (errorMsg.contains('no hay conexión') ||
          errorMsg.contains('no conectado') ||
          errorMsg.contains('socket') ||
          errorMsg.contains('closed') ||
          errorMsg.contains('broken pipe')) {
        print('💔 Conexión perdida detectada, cambiando a desconectado');
        _pollTimer?.cancel();
        _pollTimer = null;
        await _sub?.cancel();
        _sub = null;
        emit(const ConnectionState.disconnected());
      } else {
        // Error temporal, mantener conexión pero reportar error
        print('⚠️  Error temporal en comando, manteniendo conexión');
        emit(ConnectionState.error('Fallo enviando comando: $err'));

        // Verificar si la conexión sigue activa después del error
        try {
          if (await repo.isConnected()) {
            final s = state;
            if (s is Connected) {
              print('🔄 Conexión sigue activa, restaurando estado');
              emit(s);
            }
          } else {
            print('💔 Conexión perdida después del error');
            _pollTimer?.cancel();
            _pollTimer = null;
            emit(const ConnectionState.disconnected());
          }
        } catch (checkError) {
          print('❌ Error verificando conexión: $checkError');
          _pollTimer?.cancel();
          _pollTimer = null;
          emit(const ConnectionState.disconnected());
        }
      }
    }
  }

  Future<void> _onStartPolling(
      StartPolling e, Emitter<ConnectionState> emit) async {
    _pollTimer?.cancel();
    print('🔄 Iniciando polling optimizado para Tru-Test S3...');

    int tick = 0;
    // Polling más lento para S3: cada 2 segundos en lugar de 300ms
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2000), (t) {
      tick++;
      print('📊 Polling tick $tick - Enviando {RW}');
      add(SendCommandRequested('{RW}'));

      // Leer batería cada 10 ticks (cada 20 segundos)
      if (tick % 10 == 0) {
        print('🔋 Leyendo estado de batería...');
        add(SendCommandRequested('{BV}'));
        add(SendCommandRequested('{BC}'));
      }
    });
  }

  Future<void> _onStopPolling(
      StopPolling e, Emitter<ConnectionState> emit) async {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Nuevo método para verificar conexiones manuales
  Future<void> _onCheckManualConnection(
      CheckManualConnectionRequested e, Emitter<ConnectionState> emit) async {
    print('🔍 === VERIFICANDO CONEXIÓN MANUAL ===');
    print('🎯 Dispositivo: ${e.device.name} (${e.device.id})');

    // Solo verificar si no estamos ya conectados
    if (state is Connected) {
      print('✅ Ya conectado, omitiendo verificación manual');
      return;
    }

    try {
      // Verificar si hay conexión activa
      final isConnected = await repo.isConnected();

      if (isConnected) {
        print('🎉 ¡Conexión manual detectada!');

        // Emitir estado conectado
        emit(ConnectionState.connected(device: e.device));

        // Configurar escucha de datos
        _sub = repo.rawStream().listen((line) {
          add(RawLineArrived(line));
        });

        // Iniciar polling automático para la S3
        add(StartPolling());
      } else {
        print('📱 No se detectó conexión manual activa');
      }
    } catch (e) {
      print('❌ Error verificando conexión manual: $e');
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _pollTimer?.cancel();
    return super.close();
  }
}

import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/number_parsing.dart';
import '../../../domain/bluetooth_repository.dart';
import '../../../domain/entities.dart';
import '../../../data/datasources/command_registry.dart';

part 'connection_event.dart';
part 'connection_state.dart';

class ConnectionBloc extends Bloc<ConnectionEvent, ConnectionState> {
  final BluetoothRepository repo;
  final CommandRegistry _commandRegistry;
  StreamSubscription<String>? _sub;
  Timer? _pollTimer;

  // Variables para tracking (compatibilidad con código existente)
  String? _lastCommandSent;
  DateTime? _lastCommandTime;
  final Map<String, String> _commandMapping = {
    '{RW}': 'PESO',
    '{BV}': 'VOLTAJE',
    '{BC}': 'PORCENTAJE',
  };

  // 🎯 NUEVAS VARIABLES PARA POLLING SECUENCIAL
  bool _waitingForResponse = false;
  Timer? _responseTimeoutTimer;

  // ⚡ OPTIMIZACIÓN: Control de frecuencia de batería
  DateTime? _lastBatteryRequest;
  static const Duration _batteryInterval = Duration(seconds: 10);

  // 📊 ESTADÍSTICAS DE EFICIENCIA
  int _weightRequestCount = 0;
  int _batteryRequestCount = 0;

  bool _shouldRequestBattery() {
    if (_lastBatteryRequest == null) return true;
    return DateTime.now().difference(_lastBatteryRequest!) >= _batteryInterval;
  }

  ConnectionBloc(this.repo, this._commandRegistry)
      : super(const ConnectionState.disconnected()) {
    on<ConnectRequested>(_onConnect);
    on<DisconnectRequested>(_onDisconnect);
    on<RawLineArrived>(_onRawLine);
    on<SendCommandRequested>(_onSendCommand);
    on<StartPolling>(_onStartPolling);
    on<StopPolling>(_onStopPolling);
    on<CheckManualConnectionRequested>(_onCheckManualConnection);
    on<CheckAutoConnectionRequested>(_onCheckAutoConnection);
  }

  Future<void> _onConnect(
      ConnectRequested e, Emitter<ConnectionState> emit) async {
    emit(ConnectionState.connecting(device: e.device));
    await _sub?.cancel();
    _pollTimer?.cancel();

    try {
      await repo.connect(e.device.id);

      // Verificar conexión
      bool connected = false;
      for (int i = 0; i < 2; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        connected = await repo.isConnected();
        if (connected) break;
      }

      if (connected) {
        _sub = repo.rawStream().listen((line) {
          print('📥 DATOS RECIBIDOS: "$line"');
          add(RawLineArrived(line));
        }, onError: (error) {
          add(RawLineArrived('__ERROR__: $error'));
        }, onDone: () {
          add(RawLineArrived('__DISCONNECTED__'));
        });

        emit(ConnectionState.connected(device: e.device));

        // 🎯 COMANDOS INICIALES CON TRACKING DETALLADO
        print('🚀 === INICIANDO SECUENCIA DE COMANDOS INICIALES ===');

        // Comando 1: Solicitar peso inicial
        print('� 1/3 Enviando comando inicial: {RW} → Esperando PESO');
        add(SendCommandRequested('{RW}'));
        await Future.delayed(const Duration(milliseconds: 400));

        // Comando 2: Solicitar voltaje inicial
        print('📤 2/3 Enviando comando inicial: {BV} → Esperando VOLTAJE');
        add(SendCommandRequested('{BV}'));
        await Future.delayed(const Duration(milliseconds: 400));

        // Comando 3: Solicitar porcentaje inicial
        print('📤 3/3 Enviando comando inicial: {BC} → Esperando PORCENTAJE');
        add(SendCommandRequested('{BC}'));

        await Future.delayed(const Duration(milliseconds: 500));
        print('✅ Comandos iniciales completados → Iniciando polling...');
        add(StartPolling());
      } else {
        emit(ConnectionState.error(
            'La conexión no se estableció correctamente'));
      }
    } catch (err) {
      _pollTimer?.cancel();
      _pollTimer = null;
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

    // 🔍 TRACKING OPTIMIZADO: Usar CommandRegistry primero
    final timeStr = DateTime.now().toString().substring(11, 23);
    print('📊 [$timeStr] RESPUESTA: "$line"');

    // Intentar correlacionar con el registro de comandos
    final resolved = _commandRegistry.resolveWithIncoming(line);
    String correlationInfo = '';

    if (resolved != null) {
      final latency =
          resolved.resolvedAt!.difference(resolved.createdAt).inMilliseconds;
      final commandType = resolved.mappedCommand?.description ?? 'DESCONOCIDO';
      correlationInfo =
          'Comando ${resolved.rawCommand} ($commandType) → Latencia: ${latency}ms';
      print('🔗 [$timeStr] CORRELACIÓN REGISTRY: $correlationInfo');
    } else {
      // Fallback al sistema legacy
      final expectedType = _commandMapping[_lastCommandSent] ?? 'DESCONOCIDO';
      final timeSinceCommand = _lastCommandTime != null
          ? DateTime.now().difference(_lastCommandTime!).inMilliseconds
          : 0;
      correlationInfo =
          'Comando $_lastCommandSent ($expectedType) → Latencia: ${timeSinceCommand}ms';
      print('🔗 [$timeStr] CORRELACIÓN LEGACY: $correlationInfo');
    }

    if (line == '__DISCONNECTED__') {
      emit(const ConnectionState.disconnected());
      return;
    }

    // OPTIMIZACIÓN: Procesar solo datos de peso para máxima velocidad
    // Detectar formato [valor], [Uvalor] o [-valor] - PESO PRIORITARIO
    final weightRegex = RegExp(r'\[(U?-?\d+\.?\d*)\]');
    final weightMatch = weightRegex.firstMatch(line);

    if (weightMatch != null) {
      final fullValueStr = weightMatch.group(1) ?? '';
      double? value;
      WeightStatus status = WeightStatus.stable;

      if (fullValueStr.startsWith('U')) {
        status = WeightStatus.unstable;
        value = double.tryParse(fullValueStr.substring(1));
      } else if (fullValueStr.startsWith('-')) {
        status = WeightStatus.negative;
        value = double.tryParse(fullValueStr);
      } else {
        status = WeightStatus.stable;
        value = double.tryParse(fullValueStr);
      }

      if (value != null) {
        // 🎯 CORRELACIÓN INTELIGENTE: Priorizar CommandRegistry
        String? lastCommand = '';

        if (resolved != null) {
          // Usar información del CommandRegistry (más precisa)
          lastCommand = resolved.rawCommand;
        } else {
          // Fallback al sistema legacy
          lastCommand = _lastCommandSent;
        }

        final timeStr = DateTime.now().toString().substring(11, 23);

        // Prioridad 1: Correlación basada en comando conocido
        if (lastCommand == '{BV}' && value >= 1.0 && value <= 5) {
          // Comando {BV} + rango de voltaje = VOLTAJE CONFIRMADO
          print(
              '✅ [$timeStr] VOLTAJE CONFIRMADO: $value V (comando: $lastCommand) ⚡');
          emit(s.copyWith(
              batteryVoltage: BatteryStatus(volts: value, at: DateTime.now())));
          _lastCommandSent = null; // Limpiar tracking legacy
          return;
        }

        if (lastCommand == '{BC}' &&
            value >= 0 &&
            value <= 100 &&
            value % 1 == 0) {
          // Comando {BC} + rango de porcentaje = PORCENTAJE CONFIRMADO
          print(
              '✅ [$timeStr] PORCENTAJE CONFIRMADO: $value % (comando: $lastCommand) 🔋');
          emit(s.copyWith(
              batteryPercent:
                  BatteryStatus(percent: value, at: DateTime.now())));
          _lastCommandSent = null; // Limpiar tracking legacy
          return;
        }

        if (lastCommand == '{RW}') {
          // Comando {RW} = PESO CONFIRMADO
          print(
              '✅ [$timeStr] PESO CONFIRMADO: $value kg (status: $status, comando: $lastCommand) ⚖️');
          emit(s.copyWith(
              weight: WeightReading(
                  kg: value, at: DateTime.now(), status: status)));
          _lastCommandSent = null; // Limpiar tracking legacy
          return;
        }

        // Prioridad 2: Si no hay comando claro, usar rangos como antes
        if (value >= 3.0 && value <= 4.5 && value.toString().contains('.')) {
          print('🔋 VOLTAJE (por rango): $value V');
          emit(s.copyWith(
              batteryVoltage: BatteryStatus(volts: value, at: DateTime.now())));
        } else if (value >= 0 && value <= 100 && value % 1 == 0 && value < 10) {
          print('🔋 PORCENTAJE (por rango): $value %');
          emit(s.copyWith(
              batteryPercent:
                  BatteryStatus(percent: value, at: DateTime.now())));
        } else {
          print('⚖️ PESO (por defecto): $value kg (status: $status)');
          emit(s.copyWith(
              weight: WeightReading(
                  kg: value, at: DateTime.now(), status: status)));
        }
        return;
      }
    }

    // OPTIMIZACIÓN: Fallback rápido sin logs excesivos
    final kg = extractFirstNumber(line);
    if (kg != null) {
      emit(s.copyWith(
          weight: WeightReading(
              kg: kg, at: DateTime.now(), status: WeightStatus.stable)));
    }

    // 🎯 DESBLOQUEIO SECUENCIAL: Permitir envío del siguiente comando
    _unlockNextCommand();
  }

  /// 🔄 Desbloquea el envío del siguiente comando en la secuencia
  void _unlockNextCommand() {
    if (_waitingForResponse) {
      _waitingForResponse = false;
      _responseTimeoutTimer?.cancel();
      _responseTimeoutTimer = null;

      print('🔓 Respuesta recibida → Desbloqueando siguiente comando');

      // Programar el siguiente comando con un delay mínimo
      Future.delayed(const Duration(milliseconds: 100), () {
        _sendNextSequentialCommand();
      });
    }
  }

  /// 📤 Envía el siguiente comando con prioridad al peso
  void _sendNextSequentialCommand() {
    if (_waitingForResponse) return; // Ya hay un comando pendiente

    String nextCommand;

    // 🏆 PRIORIDAD AL PESO: Siempre enviar {RW} a menos que sea tiempo de batería
    if (_shouldRequestBattery()) {
      // Es momento de pedir datos de batería (cada 10 segundos)
      final batteryCommands = ['{BV}', '{BC}'];
      final batteryIndex = DateTime.now().millisecondsSinceEpoch % 2;
      nextCommand = batteryCommands[batteryIndex];
      _lastBatteryRequest = DateTime.now();

      print('🔋 Momento de batería (cada 10s): $nextCommand');
      _batteryRequestCount++;
    } else {
      // Prioridad al peso para máxima frecuencia
      nextCommand = '{RW}';
      _weightRequestCount++;
    }

    // 📊 Mostrar estadísticas cada 20 comandos de peso
    if (_weightRequestCount % 20 == 0 && _weightRequestCount > 0) {
      final efficiency = (_weightRequestCount /
              (_weightRequestCount + _batteryRequestCount) *
              100)
          .toStringAsFixed(1);
      print(
          '📊 EFICIENCIA: ${_weightRequestCount} peso vs ${_batteryRequestCount} batería → $efficiency% peso');
    }

    print(
        '🔄 Comando optimizado: $nextCommand → Prioridad: ${nextCommand == '{RW}' ? 'PESO ⚖️' : 'BATERÍA 🔋'}');
    add(SendCommandRequested(nextCommand));
  }

  Future<void> _onSendCommand(
      SendCommandRequested e, Emitter<ConnectionState> emit) async {
    try {
      if (!await repo.isConnected()) {
        _pollTimer?.cancel();
        _pollTimer = null;
        emit(const ConnectionState.disconnected());
        return;
      }

      // 🎯 TRACKING DUAL: Sistema legacy + nuevo registry
      _lastCommandSent = e.command;
      _lastCommandTime = DateTime.now();
      final expectedType = _commandMapping[e.command] ?? 'DESCONOCIDO';
      final timeStr = _lastCommandTime!.toString().substring(11, 23);

      // También registrar en el nuevo sistema
      _commandRegistry.registerOutgoing(e.command);

      print('📤 [$timeStr] ENVIANDO: ${e.command} → Esperando: $expectedType');

      // 🔒 BLOQUEO SECUENCIAL: Marcar como esperando respuesta
      _waitingForResponse = true;

      // 🛡️ TIMEOUT DE SEGURIDAD: Si no llega respuesta en 500ms, desbloquear
      _responseTimeoutTimer?.cancel();
      _responseTimeoutTimer = Timer(const Duration(milliseconds: 500), () {
        if (_waitingForResponse) {
          print(
              '⏰ TIMEOUT: Comando ${e.command} sin respuesta → Desbloqueando');
          _waitingForResponse = false;
          _sendNextSequentialCommand();
        }
      });

      // OPTIMIZACIÓN: Envío directo por BLE
      await repo.sendCommand(e.command);

      print(
          '✅ [$timeStr] COMANDO ENVIADO: ${e.command} → Aguardando respuesta...');
    } catch (err) {
      final errorMsg = err.toString().toLowerCase();

      if (errorMsg.contains('no hay conexión') ||
          errorMsg.contains('no conectado') ||
          errorMsg.contains('socket') ||
          errorMsg.contains('closed') ||
          errorMsg.contains('broken pipe')) {
        _pollTimer?.cancel();
        _pollTimer = null;
        await _sub?.cancel();
        _sub = null;
        emit(const ConnectionState.disconnected());
      } else {
        emit(ConnectionState.error('Fallo enviando comando: $err'));

        try {
          if (await repo.isConnected()) {
            final s = state;
            if (s is Connected) {
              emit(s);
            }
          } else {
            _pollTimer?.cancel();
            _pollTimer = null;
            emit(const ConnectionState.disconnected());
          }
        } catch (checkError) {
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
    _responseTimeoutTimer?.cancel();

    print('🎯 === INICIANDO POLLING OPTIMIZADO (PESO PRIORITARIO) ===');
    print('📋 Comandos: {RW} (continuo) + {BV}/{BC} (cada 10s)');

    // 🔄 NUEVO SISTEMA: Polling optimizado con prioridad al peso
    // Solo envía el primer comando, los siguientes se envían cuando llega respuesta

    // Reiniciar estado
    _waitingForResponse = false;
    _lastBatteryRequest = null; // Permitir primera solicitud de batería
    _weightRequestCount = 0; // Reiniciar estadísticas
    _batteryRequestCount = 0;

    // Iniciar la secuencia enviando el primer comando
    _sendNextSequentialCommand();
  }

  Future<void> _onStopPolling(
      StopPolling e, Emitter<ConnectionState> emit) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _responseTimeoutTimer?.cancel();
    _responseTimeoutTimer = null;
    _waitingForResponse = false;

    print('🛑 Polling secuencial detenido');
  }

  /// Nuevo método para verificar conexiones manuales
  Future<void> _onCheckManualConnection(
      CheckManualConnectionRequested e, Emitter<ConnectionState> emit) async {
    if (state is Connected) {
      return;
    }

    try {
      final isConnected = await repo.isConnected();

      if (isConnected) {
        emit(ConnectionState.connected(device: e.device));

        _sub = repo.rawStream().listen((line) {
          add(RawLineArrived(line));
        });

        add(StartPolling());
      }
    } catch (e) {
      // Error silencioso
    }
  }

  /// Nuevo método para detectar conexiones automáticas al iniciar la app
  Future<void> _onCheckAutoConnection(
      CheckAutoConnectionRequested e, Emitter<ConnectionState> emit) async {
    print('🔍 === VERIFICANDO CONEXIÓN AUTOMÁTICA AL INICIAR ===');

    // Solo verificar si no estamos ya conectados
    if (state is Connected) {
      print('✅ Ya conectado, omitiendo verificación automática');
      return;
    }

    try {
      // Verificar si hay conexión activa
      final isConnected = await repo.isConnected();
      print('📡 Estado de conexión detectado: $isConnected');

      if (isConnected) {
        print('🎉 ¡Conexión automática detectada!');

        // Crear un dispositivo dummy para S3 ya que está conectado
        final s3Device = BtDevice(
            id: 'DE:FD:76:A4:D7:ED', // MAC conocido de la S3
            name: 'S3 (Conectado)');

        // Emitir estado conectado
        emit(ConnectionState.connected(device: s3Device));

        // Configurar escucha de datos
        _sub = repo.rawStream().listen((line) {
          print('📥 DATOS AUTO-CONEXIÓN: "$line"');
          add(RawLineArrived(line));
        });

        // Iniciar polling automático
        print('🔄 Iniciando polling para conexión automática...');
        add(StartPolling());

        print('✅ Conexión automática configurada exitosamente');
      } else {
        print('📱 No se detectó conexión automática');
      }
    } catch (e) {
      print('❌ Error verificando conexión automática: $e');
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _pollTimer?.cancel();
    _responseTimeoutTimer?.cancel();
    return super.close();
  }
}

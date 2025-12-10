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

  // Seguimiento de tracking de peso
  bool _weightCommandInFlight = false;
  Timer? _weightTimeoutTimer;
  static const _weightTimeout = Duration(milliseconds: 120);
  static const _trackingGap = Duration(milliseconds: 0);

  // Timeout de inicialización (ZA1 / MSWU)
  Timer? _initTimeoutTimer;
  static const _initTimeout = Duration(milliseconds: 2000);
  String? _lastInitCommand;

  // Seguimiento de inicialización (ZA1, MSWU, y cambios de unidad)
  int _initializationStep = 0;
  // 0: ninguno
  // 1: esperando respuesta ZA1
  // 2: esperando respuesta MSWU (consulta unidad inicial)
  // 3: esperando confirmación de cambio de unidad (sin timeout)

  // 🚦 FLAG DE SUSPENSIÓN DE POLLING DE PESO
  // Cuando true: no se envían comandos de peso ni se procesan lecturas
  bool _pollingSuspended = false;

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
    on<InitTimeoutExpired>(_onInitTimeoutExpired);
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
        await Future.delayed(const Duration(milliseconds: 200));
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

        // 🎯 LIMPIO: Solo inicializar variables de peso
        print('✅ Conexión establecida → Listo para polling de peso');
        // add(StartPolling()); // ❌ DESACTIVADO - Solo iniciar cuando se necesite
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
    print('🔌 === INICIANDO DESCONEXIÓN COMPLETA ===');

    // 1. Detener polling y timers
    _pollTimer?.cancel();
    _pollTimer = null;
    _weightTimeoutTimer?.cancel();
    _weightCommandInFlight = false;

    // 2. Cancelar suscripción al stream de datos
    if (_sub != null) {
      print('📴 Cancelando suscripción al stream de datos...');
      await _sub?.cancel();
      _sub = null;
    }

    // 3. Limpiar CommandRegistry
    print('🧹 Limpiando registro de comandos...');
    _commandRegistry.purgeTimeouts();

    // 4. Resetear estadísticas y variables de tracking
    // (ninguna para este bloc - solo peso)

    // 🚀 Resetear estado de polling
    _pollingSuspended = false;

    // 5. Desconectar del repositorio (esto llamará al BLE adapter)
    print('🔌 Desconectando del dispositivo...');
    try {
      await repo.disconnect();
      print('✅ Dispositivo desconectado correctamente');
    } catch (error) {
      print('⚠️ Error durante desconexión: $error');
    }

    // 6. Emitir estado de desconectado
    emit(const ConnectionState.disconnected());
    print('✅ === DESCONEXIÓN COMPLETA FINALIZADA ===');
  }

  void _onRawLine(RawLineArrived e, Emitter<ConnectionState> emit) {
    final s = state;
    if (s is! Connected) return;
    final line = e.line.trim();

    if (line == '__DISCONNECTED__') {
      _weightTimeoutTimer?.cancel();
      _weightCommandInFlight = false;
      emit(const ConnectionState.disconnected());
      return;
    }

    print('📥 Línea recibida: "$line" | InitStep: $_initializationStep');

    // ═══════════════════════════════════════════════════════════
    // MANEJO DE INICIALIZACIÓN {ZA1} → {MSWU}
    // ═══════════════════════════════════════════════════════════
    if (_initializationStep == 1) {
      // Esperando respuesta de {ZA1}
      // Respuesta típica: "^" (ACK) o similar
      if (line == '^' || line.contains('ACK') || line.isNotEmpty) {
        print('✅ INIT Paso 1: {ZA1} confirmado (ACK: $line)');
        _initTimeoutTimer?.cancel();
        _initializationStep = 2;
        // Enviar siguiente comando: {MSWU} para consultar unidades
        print('➡️ INIT Paso 2: Enviando {MSWU}...');
        add(SendCommandRequested('{MSWU}'));
        return;
      }
    } else if (_initializationStep == 2) {
      // Esperando respuesta de {MSWU}
      // Respuesta típica: "kg" o "lb" o "^" (ACK de cambio)
      final lower = line.toLowerCase();
      if (lower.contains('kg') || lower.contains('lb') || line == '^') {
        print('✅ INIT Paso 2: {MSWU} recibido: $line');
        _initTimeoutTimer?.cancel();
        String? unit;
        if (lower.contains('lb')) {
          unit = 'lb';
        } else if (lower.contains('kg')) {
          unit = 'kg';
        } else if (line == '^') {
          if (_lastInitCommand == ScaleCommand.setUnitLb.code) {
            unit = 'lb';
          } else if (_lastInitCommand == ScaleCommand.setUnitKg.code) {
            unit = 'kg';
          } else {
            // ACK sin pista: si no sabemos, conservar previa
            unit = s.weightUnit;
          }
        }
        emit(s.copyWith(weightUnit: unit ?? s.weightUnit));
        _initializationStep = 0; // INICIALIZACIÓN COMPLETADA
        print('🎉 INIT: Secuencia completada. Iniciando polling de peso...');
        // Reiniciar polling de peso
        _sendNextWeightCommand();
        return;
      }
    } else if (_initializationStep == 3) {
      // Esperando confirmación ^ de cambio de unidad (SIN TIMEOUT)
      if (line == '^') {
        print('✅ Confirmación de cambio de unidad recibida');
        _initTimeoutTimer?.cancel();
        String? unit;
        if (_lastInitCommand == ScaleCommand.setUnitLb.code) {
          unit = 'lb';
        } else if (_lastInitCommand == ScaleCommand.setUnitKg.code) {
          unit = 'kg';
        }
        if (unit != null) {
          emit(s.copyWith(weightUnit: unit));
        }
        _initializationStep = 0;
        print('🎉 Cambio de unidad completado. Reanudando polling de peso...');
        _sendNextWeightCommand();
        return;
      }
    }

    // ═══════════════════════════════════════════════════════════
    // MODO NORMAL: PROCESAR PESO (solo si NO está en inicialización)
    // ═══════════════════════════════════════════════════════════
    if (_initializationStep != 0) {
      // Aún en inicialización, ignorar línea
      return;
    }

    // Si el polling está suspendido, no procesar peso
    if (_pollingSuspended) {
      return;
    }

    print('📥 PESO: "$line"');

    // 🚨 SOBRECARGA [---]
    if (line.trim() == '[---]') {
      print('⚠️ SOBRECARGA DETECTADA: [---]');
      emit(s.copyWith(
          weight: WeightReading(
              kg: null, at: DateTime.now(), status: WeightStatus.overload)));
      _completeWeightCommandCycle();
      return;
    }

    // ⚖️ PESO: Detectar [valor], [Uvalor], [-valor]
    final weightRegex = RegExp(r'\[(U?-?\d+\.?\d*\s*)\]');
    final weightMatch = weightRegex.firstMatch(line);

    if (weightMatch != null) {
      final fullValueStr = (weightMatch.group(1) ?? '').trim();
      double? value;
      WeightStatus status = WeightStatus.stable;

      if (fullValueStr.startsWith('U')) {
        status = WeightStatus.unstable;
        value = double.tryParse(fullValueStr.substring(1).trim());
        print('📊 PESO INESTABLE: $value kg');
      } else if (fullValueStr.startsWith('-')) {
        status = WeightStatus.negative;
        value = double.tryParse(fullValueStr.trim());
        print('📊 PESO NEGATIVO: $value kg');
      } else {
        status = WeightStatus.stable;
        value = double.tryParse(fullValueStr.trim());
        print('📊 PESO ESTABLE: $value kg');
      }

      if (value != null) {
        emit(s.copyWith(
            weight:
                WeightReading(kg: value, at: DateTime.now(), status: status)));
      }
      _completeWeightCommandCycle();
      return;
    }

    // Fallback: Intentar extraer número si no está entre corchetes
    final kg = extractFirstNumber(line);
    if (kg != null) {
      emit(s.copyWith(
          weight: WeightReading(
              kg: kg, at: DateTime.now(), status: WeightStatus.stable)));
      _completeWeightCommandCycle();
    }
  }

  Future<void> _onSendCommand(
      SendCommandRequested e, Emitter<ConnectionState> emit) async {
    try {
      if (!await repo.isConnected()) {
        _pollTimer?.cancel();
        _pollTimer = null;
        _weightTimeoutTimer?.cancel();
        _weightCommandInFlight = false;
        emit(const ConnectionState.disconnected());
        return;
      }

      final isInitializationCommand = e.command == '{ZA1}' ||
          e.command == '{MSWU}' ||
          e.command == ScaleCommand.setUnitKg.code ||
          e.command == ScaleCommand.setUnitLb.code;
      final isWeightCommand =
          e.command == ScaleCommand.readWeight.code; // '{RW}'

      if (isInitializationCommand) {
        print('📤 INIT: Enviando ${e.command}');
        _lastInitCommand = e.command;
        final isSetUnitCommand = e.command == ScaleCommand.setUnitKg.code ||
            e.command == ScaleCommand.setUnitLb.code;

        if (e.command == '{ZA1}') {
          _initializationStep = 1; // Esperando respuesta ZA1
          _startInitTimeout(1);
        } else if (e.command == '{MSWU}') {
          _initializationStep = 2; // Esperando respuesta MSWU
          _startInitTimeout(2);
        } else if (isSetUnitCommand) {
          // 🟢 Cambio de unidad: esperar confirmación ^ (SIN TIMEOUT)
          _initTimeoutTimer?.cancel();
          _initializationStep = 3;
          print(
              '📤 Esperando confirmación de cambio de unidad (sin timeout)...');
        }
      } else if (isWeightCommand) {
        print('📤 PESO: Enviando ${e.command}');
        _weightCommandInFlight = true;
        _startWeightTimeoutWatchdog();
      } else {
        print('📤 COMANDO: Enviando ${e.command}');
      }

      // Registrar en CommandRegistry
      _commandRegistry.registerOutgoing(e.command);

      // Enviar comando
      await repo.sendCommand(e.command);
      print('✅ PESO: Comando ${e.command} enviado');
    } catch (err) {
      final errorMsg = err.toString().toLowerCase();

      if (errorMsg.contains('no hay conexión') ||
          errorMsg.contains('no conectado') ||
          errorMsg.contains('socket') ||
          errorMsg.contains('closed') ||
          errorMsg.contains('broken pipe')) {
        _pollTimer?.cancel();
        _pollTimer = null;
        _weightTimeoutTimer?.cancel();
        _weightCommandInFlight = false;
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
            _weightTimeoutTimer?.cancel();
            _weightCommandInFlight = false;
            emit(const ConnectionState.disconnected());
          }
        } catch (checkError) {
          _pollTimer?.cancel();
          _pollTimer = null;
          _weightTimeoutTimer?.cancel();
          _weightCommandInFlight = false;
          emit(const ConnectionState.disconnected());
        }
      }
    }
  }

  Future<void> _onStartPolling(
      StartPolling e, Emitter<ConnectionState> emit) async {
    _pollTimer?.cancel();
    _weightTimeoutTimer?.cancel();
    _initTimeoutTimer?.cancel();

    _pollingSuspended = false;
    _weightCommandInFlight = false;
    _initializationStep = 0;

    print('🎯 === INICIANDO POLLING CON INICIALIZACIÓN ===');

    // Paso 1: Enviar {ZA1} para habilitar confirmación de comandos
    print('📤 Paso 1: Enviando {ZA1} (confirmación de comandos)');
    add(SendCommandRequested('{ZA1}'));
  }

  void _onInitTimeoutExpired(
      InitTimeoutExpired e, Emitter<ConnectionState> emit) {
    // Solo actuar si seguimos en el mismo paso
    if (_initializationStep != e.step) return;

    if (e.step == 1) {
      print('⏰ INIT Timeout en ZA1, forzando avance a MSWU');
      _initializationStep = 2;
      add(SendCommandRequested('{MSWU}'));
    } else if (e.step == 2) {
      print('⏰ INIT Timeout en MSWU, infiriendo unidad del último comando');
      if (state is Connected) {
        String? unit;
        if (_lastInitCommand == ScaleCommand.setUnitLb.code) {
          unit = 'lb';
        } else if (_lastInitCommand == ScaleCommand.setUnitKg.code) {
          unit = 'kg';
        } else {
          unit = (state as Connected).weightUnit; // fallback
        }
        emit((state as Connected).copyWith(weightUnit: unit));
      }
      _initializationStep = 0;
      _sendNextWeightCommand();
    }
  }

  Future<void> _onStopPolling(
      StopPolling e, Emitter<ConnectionState> emit) async {
    print('🛑 === DETENIENDO POLLING ===');

    _pollTimer?.cancel();
    _pollTimer = null;
    _weightTimeoutTimer?.cancel();
    _initTimeoutTimer?.cancel();
    _weightCommandInFlight = false;
    _pollingSuspended = true;

    print('🛑 Polling de peso detenido');
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
    print('🔒 === CERRANDO CONNECTION BLOC ===');

    // 1. Cancelar timers
    _pollTimer?.cancel();
    _weightTimeoutTimer?.cancel();

    // 2. Cancelar suscripción
    await _sub?.cancel();

    // 3. Desconectar si es necesario
    try {
      final isConnected = await repo.isConnected();
      if (isConnected) {
        print('🔌 Desconectando...');
        await repo.disconnect();
      }
    } catch (error) {
      print('⚠️ Error durante close: $error');
    }

    print('✅ ConnectionBloc cerrado');
    return super.close();
  }

  void _startWeightTimeoutWatchdog() {
    _weightTimeoutTimer?.cancel();
    _weightTimeoutTimer = Timer(_weightTimeout, () {
      if (_pollingSuspended) return;
      _weightCommandInFlight = false;
      _sendNextWeightCommand();
    });
  }

  void _completeWeightCommandCycle() {
    _weightTimeoutTimer?.cancel();
    _weightCommandInFlight = false;
    if (_pollingSuspended) return;
    Future.delayed(_trackingGap, _sendNextWeightCommand);
  }

  void _startInitTimeout(int step) {
    _initTimeoutTimer?.cancel();
    _initTimeoutTimer = Timer(_initTimeout, () {
      add(InitTimeoutExpired(step));
    });
  }

  void _sendNextWeightCommand() {
    if (_pollingSuspended || _weightCommandInFlight) return;
    add(SendCommandRequested(ScaleCommand.readWeight.code));
  }
}

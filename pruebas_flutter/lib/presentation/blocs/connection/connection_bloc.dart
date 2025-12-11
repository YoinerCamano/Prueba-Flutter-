import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/number_parsing.dart';
import '../../../domain/bluetooth_repository.dart';
import '../../../domain/entities.dart';
import '../../../data/datasources/command_registry.dart';
import '../../../data/datasources/scale_model_registry.dart';
import '../../../data/datasources/scale_profile_holder.dart';

part 'connection_event.dart';
part 'connection_state.dart';

class ConnectionBloc extends Bloc<ConnectionEvent, ConnectionState> {
  final BluetoothRepository repo;
  final CommandRegistry _commandRegistry;
  final ScaleModelRegistry _scaleRegistry;
  final ScaleProfileHolder _profileHolder;
  StreamSubscription<String>? _sub;
  Timer? _pollTimer;

  // Seguimiento de tracking de peso
  bool _weightCommandInFlight = false;
  Timer? _weightTimeoutTimer;
  static const _weightTimeout = Duration(milliseconds: 120);
  static const _trackingGap = Duration(milliseconds: 0);
  String? _pendingWeightFragment;

  // Timeout de inicialización (ZA1 / SPWU)
  Timer? _initTimeoutTimer;
  static const _initTimeout = Duration(milliseconds: 2000);
  String? _lastInitCommand;

  // Seguimiento de inicialización (ZA1, SPWU, y cambios de unidad)
  int _initializationStep = 0;
  // 0: ninguno
  // 1: esperando respuesta ZA1
  // 2: esperando respuesta SPWU (consulta unidad inicial)
  // 3: esperando confirmación de cambio de unidad (sin timeout)

  // 🚦 FLAG DE SUSPENSIÓN DE POLLING DE PESO
  // Cuando true: no se envían comandos de peso ni se procesan lecturas
  bool _pollingSuspended = false;

  static const int _ew7StepZa1 = 11;
  static const int _ew7StepErrors = 12;
  static const int _ew7StepCarriageReturn = 13;

  ConnectionBloc(this.repo, this._commandRegistry, this._scaleRegistry,
      this._profileHolder)
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

  bool get _isEzi => _profileHolder.current.id == ScaleModelRegistry.eziWeighId;

  Future<void> _onConnect(
      ConnectRequested e, Emitter<ConnectionState> emit) async {
    final descriptor = _scaleRegistry.guessFromDevice(e.device);
    _profileHolder.update(descriptor);
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

        emit(ConnectionState.connected(device: e.device, scale: descriptor));

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
    _pendingWeightFragment = null;

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
    _initializationStep = 0;
    _initTimeoutTimer?.cancel();

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
    // Limpia retornos de carro / saltos de línea para evitar ruido en parsers
    var line = e.line.replaceAll(RegExp(r'[\r\n]+'), '').trim();

    if (line == '__DISCONNECTED__') {
      _weightTimeoutTimer?.cancel();
      _weightCommandInFlight = false;
      emit(const ConnectionState.disconnected());
      return;
    }

    if (line.isEmpty) {
      // Línea solo con retorno de carro: ignorar
      print('⚠️ Línea vacía tras limpieza CR/LF, se ignora');
      return;
    }

    print(
        '📥 Línea recibida: "$line" | InitStep: $_initializationStep | EZI=${_isEzi}');

    // Unir fragmentos de peso antes de procesar init/peso
    if (line.startsWith('[') && !line.contains(']')) {
      _pendingWeightFragment = line;
      return;
    }
    if (_pendingWeightFragment != null && line.contains(']')) {
      line = (_pendingWeightFragment! + line).replaceAll(RegExp(r'\s+'), '');
      _pendingWeightFragment = null;
    } else if (_isEzi && !line.contains(']')) {
      // EW7 puede enviar fragmentos sin corchetes completos
      _pendingWeightFragment = _pendingWeightFragment != null
          ? _pendingWeightFragment! + line
          : line;
      return;
    } else if (_isEzi && _pendingWeightFragment != null && line.contains(']')) {
      line = (_pendingWeightFragment! + line).replaceAll(RegExp(r'\s+'), '');
      _pendingWeightFragment = null;
    }

    final maybeWeightPattern = line.contains('[') && line.contains(']');

    // ═══════════════════════════════════════════════════════════
    // MANEJO DE INICIALIZACIÓN {ZA1} → {SPWU} y EW7
    // ═══════════════════════════════════════════════════════════
    if (_initializationStep == _ew7StepZa1 && _isEzi) {
      // EW7: Esperando respuesta de {ZA1}
      if (line.isNotEmpty) {
        print('✅ EW7: {ZA1} respondido: $line');
        _initTimeoutTimer?.cancel();
        _initializationStep = _ew7StepErrors;
        print('➡️ EW7: Solicitando errores con {ZE1}...');
        add(SendCommandRequested(ScaleCommand.getErrors.code));
        return;
      }
    } else if (_initializationStep == _ew7StepErrors && _isEzi) {
      // EW7: Respuesta de errores {ZE1}
      print('🧾 EW7: Respuesta {ZE1}: $line');
      _initTimeoutTimer?.cancel();
      _initializationStep = _ew7StepCarriageReturn;
      print('➡️ EW7: Estableciendo retorno de carro {ZC1}...');
      add(SendCommandRequested(ScaleCommand.setCarriageReturn.code));
      return;
    } else if (_initializationStep == _ew7StepCarriageReturn && _isEzi) {
      // EW7: Esperando confirmación de {ZC1}
      if (line.isNotEmpty) {
        print('✅ EW7: {ZC1} confirmado: $line');
        _initTimeoutTimer?.cancel();
        _initializationStep = 0;
        _sendNextWeightCommand();
        return;
      }
    } else if (_initializationStep == 1) {
      // Esperando respuesta de {ZA1}
      // Respuesta típica: "^" (ACK) o similar
      if (line == '^' || line.contains('ACK') || line.isNotEmpty) {
        print('✅ INIT Paso 1: {ZA1} confirmado (ACK: $line)');
        _initTimeoutTimer?.cancel();
        _initializationStep = 2;
        // Enviar siguiente comando: {SPWU} para consultar unidades
        print('➡️ INIT Paso 2: Enviando {SPWU}...');
        add(SendCommandRequested('{SPWU}'));
        return;
      }
    } else if (_initializationStep == 2) {
      // Esperando respuesta de {SPWU}
      // Respuesta típica: "kg" o "lb" o "^" (ACK de cambio)
      final lower = line.toLowerCase();
      if (lower.contains('0') || lower.contains('1') || line == '^') {
        print('✅ INIT Paso 2: {SPWU} recibido: $line');
        _initTimeoutTimer?.cancel();
        String? unit;
        if (lower.contains('1')) {
          unit = 'lb';
        } else if (lower.contains('0')) {
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
      // Para EW7 permitimos procesar peso aunque la secuencia siga en curso
      if (!_isEzi ||
          (!maybeWeightPattern && extractFirstNumber(line) == null)) {
        return;
      }
      _initializationStep = 0;
      _initTimeoutTimer?.cancel();
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
          e.command == '{SPWU}' ||
          e.command == ScaleCommand.setUnitKg.code ||
          e.command == ScaleCommand.setUnitLb.code ||
          e.command == ScaleCommand.getErrors.code ||
          e.command == ScaleCommand.setCarriageReturn.code;
      final isWeightCommand =
          e.command == ScaleCommand.readWeight.code; // '{RW}'

      if (isInitializationCommand) {
        print('📤 INIT: Enviando ${e.command}');
        _lastInitCommand = e.command;
        final isSetUnitCommand = e.command == ScaleCommand.setUnitKg.code ||
            e.command == ScaleCommand.setUnitLb.code;

        if (e.command == '{ZA1}') {
          _initializationStep =
              _isEzi ? _ew7StepZa1 : 1; // Esperando respuesta ZA1
          _startInitTimeout(_initializationStep);
        } else if (e.command == '{SPWU}') {
          _initializationStep = 2; // Esperando respuesta SPWU
          _startInitTimeout(2);
        } else if (e.command == ScaleCommand.getErrors.code) {
          _initializationStep = _ew7StepErrors;
          _startInitTimeout(_ew7StepErrors);
        } else if (e.command == ScaleCommand.setCarriageReturn.code) {
          _initializationStep = _ew7StepCarriageReturn;
          _startInitTimeout(_ew7StepCarriageReturn);
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
    if (_isEzi) {
      print(
          '📤 EW7: Enviando secuencia {ZA1} → {ZE1} → {ZC1} antes de leer peso');
      _initializationStep = _ew7StepZa1;
      add(SendCommandRequested(ScaleCommand.enableAcknowledgment.code));
      return;
    }

    print('📤 Paso 1: Enviando {ZA1} (confirmación de comandos)');
    add(SendCommandRequested(ScaleCommand.enableAcknowledgment.code));
  }

  void _onInitTimeoutExpired(
      InitTimeoutExpired e, Emitter<ConnectionState> emit) {
    // Solo actuar si seguimos en el mismo paso
    if (_initializationStep != e.step) return;

    if (e.step == 1) {
      print('⏰ INIT Timeout en ZA1, forzando avance a SPWU');
      _initializationStep = 2;
      add(SendCommandRequested('{SPWU}'));
    } else if (e.step == 2) {
      print('⏰ INIT Timeout en SPWU, infiriendo unidad del último comando');
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
    } else if (e.step == _ew7StepZa1) {
      print('⏰ EW7: Timeout esperando ZA1, enviando ZE1 igualmente');
      _initializationStep = _ew7StepErrors;
      add(SendCommandRequested(ScaleCommand.getErrors.code));
    } else if (e.step == _ew7StepErrors) {
      print('⏰ EW7: Timeout esperando ZE1, avanzando a ZC1');
      _initializationStep = _ew7StepCarriageReturn;
      add(SendCommandRequested(ScaleCommand.setCarriageReturn.code));
    } else if (e.step == _ew7StepCarriageReturn) {
      print('⏰ EW7: Timeout esperando ZC1, iniciando polling de peso');
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
        final descriptor = _scaleRegistry.guessFromDevice(e.device);
        _profileHolder.update(descriptor);
        emit(ConnectionState.connected(device: e.device, scale: descriptor));

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
        _profileHolder.update(ScaleModelRegistry.truTestS3);
        emit(ConnectionState.connected(
            device: s3Device, scale: ScaleModelRegistry.truTestS3));

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
    _pendingWeightFragment = null;
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

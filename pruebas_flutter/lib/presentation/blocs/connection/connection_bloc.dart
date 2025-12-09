import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/number_parsing.dart';
import '../../../domain/bluetooth_repository.dart';
import '../../../domain/entities.dart';
import '../../../data/datasources/command_registry.dart';
import '../../../data/datasources/scale_model_registry.dart';
import '../../../data/datasources/scale_profile_holder.dart';
import '../../../data/datasources/scale_connection_strategy.dart';

part 'connection_event.dart';
part 'connection_state.dart';

class ConnectionBloc extends Bloc<ConnectionEvent, ConnectionState> {
  final BluetoothRepository repo;
  final CommandRegistry _commandRegistry;
  final ScaleModelRegistry _scaleRegistry;
  final ScaleProfileHolder _profileHolder;
  StreamSubscription<String>? _sub;
  Timer? _pollTimer;
  Timer? _modelTimeoutTimer;

  // Seguimiento de tracking de peso
  bool _weightCommandInFlight = false;
  Timer? _weightTimeoutTimer;
  static const _weightTimeout = Duration(milliseconds: 120);
  static const _trackingGap = Duration(milliseconds: 0);

  // Timeout de inicializacion (ZA1 / MSWU)
  Timer? _initTimeoutTimer;
  static const _initTimeout = Duration(milliseconds: 2000);
  String? _lastInitCommand;

  // Seguimiento de inicializacion (ZA1, MSWU, y cambios de unidad)
  int _initializationStep = 0;
  // 0: ninguno
  // 1: esperando respuesta ZA1
  // 2: esperando respuesta MSWU (consulta unidad inicial)
  // 3: esperando confirmacion de cambio de unidad (sin timeout)

  static const _modelCommand = '{ZN}';
  bool _waitingModelResponse = false;
  late ScaleDescriptor _activeScale;

  // 🎯 ESTRATEGIA DE CONEXIÓN SEGÚN MODELO
  ScaleConnectionStrategy? _strategy;

  // FLAG DE SUSPENSION DE POLLING DE PESO
  // Cuando true: no se envian comandos de peso ni se procesan lecturas
  bool _pollingSuspended = false;

  ConnectionBloc(this.repo, this._commandRegistry, this._scaleRegistry,
      this._profileHolder)
      : super(const ConnectionState.disconnected()) {
    _activeScale = ScaleModelRegistry.unknown;
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
    _activeScale = _scaleRegistry.guessFromDevice(e.device);
    _profileHolder.update(_activeScale);

    // 🎯 Crear estrategia según el modelo detectado
    _strategy = ScaleStrategyFactory.create(
      repository: repo,
      descriptor: _activeScale,
    );

    emit(ConnectionState.connecting(device: e.device));
    await _sub?.cancel();
    _pollTimer?.cancel();
    _waitingModelResponse = false;

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

        emit(ConnectionState.connected(device: e.device, scale: _activeScale));

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
    print('?Y"O === INICIANDO DESCONEXION COMPLETA ===');

    _pollTimer?.cancel();
    _pollTimer = null;
    _weightTimeoutTimer?.cancel();
    _weightCommandInFlight = false;
    _modelTimeoutTimer?.cancel();
    _waitingModelResponse = false;

    if (_sub != null) {
      print('?Y"? Cancelando suscripcion al stream de datos...');
      await _sub?.cancel();
      _sub = null;
    }

    print('?Y?? Limpiando registro de comandos...');
    _commandRegistry.purgeTimeouts();

    _pollingSuspended = false;
    _activeScale = ScaleModelRegistry.unknown;
    _profileHolder.update(_activeScale);
    _strategy?.reset();
    _strategy = null;

    print('?Y"O Desconectando del dispositivo...');
    try {
      await repo.disconnect();
      print('?o. Dispositivo desconectado correctamente');
    } catch (error) {
      print('?s???? Error durante desconexion: $error');
    }

    emit(const ConnectionState.disconnected());
    print('?o. === DESCONEXION COMPLETA FINALIZADA ===');
  }

  void _onRawLine(RawLineArrived e, Emitter<ConnectionState> emit) {
    final s = state;
    if (s is! Connected) return;
    final rawLine = e.line.trim();

    print(
        '📥 RAW: "$rawLine" | Estrategia: ${_strategy?.descriptor.id} | InFlight: $_weightCommandInFlight');

    if (rawLine == '__DISCONNECTED__') {
      _weightTimeoutTimer?.cancel();
      _weightCommandInFlight = false;
      _strategy?.reset();
      emit(const ConnectionState.disconnected());
      return;
    }

    // 🎯 DELEGAR PROCESAMIENTO A LA ESTRATEGIA DEL MODELO
    final processedLine = _strategy?.processRawLine(rawLine);

    if (processedLine == null) {
      // La estrategia necesita más datos (fragmentación en progreso)
      // Bloquear siguiente comando si la estrategia lo requiere
      if (_strategy?.needsCommandTracking('{RW}') ?? false) {
        _weightCommandInFlight = true;
        print(
            '🔒 BLOQUEADO: Esperando más fragmentos, _weightCommandInFlight = true');
      }
      return;
    }

    // Línea completa lista para procesar
    print('📨 PROCESANDO: "$processedLine"');
    _processCompleteLine(processedLine, s, emit);

    // NOTA: _completeWeightCommandCycle() se llama dentro de _processCompleteLine
    // cuando detecta un peso válido, sobrecarga o número
  }

  void _processCompleteLine(
      String line, Connected s, Emitter<ConnectionState> emit) {
    print('📥 Procesando línea completa: "$line"');

    // 🔍 DETECCIÓN DE RESPUESTA AL COMANDO {ZN} (modelo de báscula)
    if (_waitingModelResponse) {
      _modelTimeoutTimer?.cancel();
      _waitingModelResponse = false;

      print('✅ Respuesta de modelo recibida: "$line"');
      final descriptor = _scaleRegistry.resolveFromModelResponse(line,
          hintTransport: _scaleRegistry.chooseTransport(
              deviceId: s.device.id, descriptor: _activeScale));
      _activeScale = descriptor;
      _profileHolder.update(descriptor);

      // 🎯 Actualizar estrategia con el modelo detectado
      _strategy = ScaleStrategyFactory.create(
        repository: repo,
        descriptor: descriptor,
      );

      emit(s.copyWith(scale: descriptor));
      _kickoffInitialization();
      return;
    }

    // Fallback: si llega una línea con el modelo y ya no estamos esperando, detectarlo igual
    final modelHint = line.toUpperCase();
    final looksLikeModel =
        modelHint.contains('EZIWEIGH') || modelHint.contains('EZI');
    if (!_waitingModelResponse && looksLikeModel) {
      final descriptor = _scaleRegistry.resolveFromModelResponse(line,
          hintTransport: _scaleRegistry.chooseTransport(
              deviceId: s.device.id, descriptor: _activeScale));
      _activeScale = descriptor;
      _profileHolder.update(descriptor);

      // 🎯 Actualizar estrategia con el modelo detectado
      _strategy = ScaleStrategyFactory.create(
        repository: repo,
        descriptor: descriptor,
      );

      emit(s.copyWith(scale: descriptor));
      _kickoffInitialization();
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

    print('🔍 Buscando peso en: "$line" | Match: ${weightMatch != null}');

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

      final normalized = _normalizeCommand(e.command);
      print(
          '🔧 Comando solicitado: "${e.command}" | Normalizado: "$normalized" | Modelo: ${_activeScale.id}');

      if (!_scaleRegistry.isCommandSupported(_activeScale, normalized)) {
        print('?s? Command $normalized no soportado por ${_activeScale.id}');
        if (_waitingModelResponse && normalized == _modelCommand) {
          _waitingModelResponse = false;
          _kickoffInitialization();
        }
        return;
      }

      final commandToSend = _scaleRegistry.mapCommand(_activeScale, normalized);
      print('📋 Comando después de mapeo: "$commandToSend"');

      final isInitializationCommand = commandToSend == '{ZA1}' ||
          commandToSend == '{MSWU}' ||
          commandToSend == ScaleCommand.setUnitKg.code ||
          commandToSend == ScaleCommand.setUnitLb.code;
      final isWeightCommand = commandToSend == ScaleCommand.readWeight.code ||
          commandToSend == 'RW'; // '{RW}' o RW plano

      if (isInitializationCommand) {
        print('?Y"? INIT: Enviando $commandToSend');
        _lastInitCommand = commandToSend;
        final isSetUnitCommand = commandToSend == ScaleCommand.setUnitKg.code ||
            commandToSend == ScaleCommand.setUnitLb.code;

        if (commandToSend == '{ZA1}') {
          _initializationStep = 1; // Esperando respuesta ZA1
          _startInitTimeout(1);
        } else if (commandToSend == '{MSWU}') {
          _initializationStep = 2; // Esperando respuesta MSWU
          _startInitTimeout(2);
        } else if (isSetUnitCommand) {
          _initTimeoutTimer?.cancel();
          _initializationStep = 3;
          print(
              '?Y"? Esperando confirmacion de cambio de unidad (sin timeout)...');
        }
      } else if (isWeightCommand) {
        print('?Y"? PESO: Enviando $commandToSend');
        _weightCommandInFlight = true;
        _startWeightTimeoutWatchdog();
      } else {
        print('?Y"? COMANDO: Enviando $commandToSend');
      }

      // Registrar en CommandRegistry
      _commandRegistry.registerOutgoing(commandToSend);

      // Enviar comando
      await repo.sendCommand(commandToSend);
      print('?o. PESO: Comando $commandToSend enviado');
    } catch (err) {
      final errorMsg = err.toString().toLowerCase();

      if (errorMsg.contains('no hay conexi') ||
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
    _modelTimeoutTimer?.cancel();

    _pollingSuspended = false;
    _weightCommandInFlight = false;
    _initializationStep = 0;
    _waitingModelResponse = false;

    print('?YZ? === INICIANDO POLLING CON INICIALIZACION ===');

    if (_scaleRegistry.isCommandSupported(_activeScale, _modelCommand)) {
      _waitingModelResponse = true;
      print('?Y"? Paso 0: Enviando $_modelCommand (consulta de modelo)');
      add(SendCommandRequested(_modelCommand));
      _modelTimeoutTimer = Timer(const Duration(milliseconds: 1500), () {
        if (_waitingModelResponse) {
          print('??? Timeout esperando modelo, continuando inicializacion');
          _waitingModelResponse = false;
          _kickoffInitialization();
        }
      });
    } else {
      _kickoffInitialization();
    }
  }

  void _kickoffInitialization() {
    final supportsAck =
        _scaleRegistry.isCommandSupported(_activeScale, '{ZA1}');
    final supportsUnits =
        _scaleRegistry.isCommandSupported(_activeScale, '{MSWU}');

    if (supportsAck) {
      print('?Y"? Paso 1: Enviando {ZA1} (confirmacion de comandos)');
      add(SendCommandRequested('{ZA1}'));
      return;
    }

    if (supportsUnits) {
      print('?Y"? Paso 1: Sin ACK, consultando unidad {MSWU}');
      add(SendCommandRequested('{MSWU}'));
      return;
    }

    print('?Y"? Modelo sin init especial, iniciando polling de peso');
    _initializationStep = 0;
    _sendNextWeightCommand();
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
    _modelTimeoutTimer?.cancel();
    _weightCommandInFlight = false;
    _waitingModelResponse = false;
    _strategy?.reset();
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
        _activeScale = _scaleRegistry.guessFromDevice(e.device);
        _profileHolder.update(_activeScale);
        emit(ConnectionState.connected(device: e.device, scale: _activeScale));

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

        _activeScale = ScaleModelRegistry.truTestS3;
        _profileHolder.update(_activeScale);
        // Emitir estado conectado
        emit(ConnectionState.connected(device: s3Device, scale: _activeScale));

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
    print('=== CERRANDO CONNECTION BLOC ===');

    // 1. Cancelar timers
    _pollTimer?.cancel();
    _weightTimeoutTimer?.cancel();
    _modelTimeoutTimer?.cancel();

    // 2. Cancelar suscripcion
    await _sub?.cancel();

    // 3. Desconectar si es necesario
    try {
      final isConnected = await repo.isConnected();
      if (isConnected) {
        print('?Y"O Desconectando...');
        await repo.disconnect();
      }
    } catch (error) {
      print('?s???? Error durante close: $error');
    }

    print('?o. ConnectionBloc cerrado');
    return super.close();
  }

  String _normalizeCommand(String raw) => raw.trim().toUpperCase();

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
    if (_pollingSuspended || _weightCommandInFlight || _waitingModelResponse) {
      return;
    }
    add(SendCommandRequested(ScaleCommand.readWeight.code));
  }
}

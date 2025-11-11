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

  // 🚦 FLAG DE SUSPENSIÓN TOTAL DE POLLING DE PESO/BATERÍA
  // Cuando true: no se envían comandos automáticos {RW}/{BV}/{BC} ni se procesan lecturas de peso
  bool _pollingSuspended = false;

  // 🚀 SECUENCIA INICIAL: Control de comandos de inicio
  int _initialSequenceStep = 0;
  bool _isInitialSequence = false;

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

        // 🎯 INICIALIZACIÓN: Reiniciar variables de tracking para nueva conexión
        print(
            '🚀 === INICIANDO SECUENCIA DE COMANDOS INICIALES CON TRACKING ===');
        _waitingForResponse = false;
        _responseTimeoutTimer?.cancel();
        _responseTimeoutTimer = null;
        _lastBatteryRequest = null;
        _weightRequestCount = 0;
        _batteryRequestCount = 0;

        // 🔄 NO INICIAR POLLING AUTOMÁTICAMENTE
        // El polling se iniciará solo cuando se necesite (ej: ver WeightCard)
        await Future.delayed(const Duration(milliseconds: 300));

        print(
            '✅ Conexión estabilizada → Polling NO iniciado (se inicia bajo demanda)');
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
    _responseTimeoutTimer?.cancel();
    _responseTimeoutTimer = null;
    _waitingForResponse = false;

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
    _lastCommandSent = null;
    _lastCommandTime = null;
    _lastBatteryRequest = null;
    _weightRequestCount = 0;
    _batteryRequestCount = 0;

    // 🚀 Resetear secuencia inicial
    _isInitialSequence = false;
    _initialSequenceStep = 0;

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

    // 🔧 PRIORIDAD 1: Procesar comandos de información del dispositivo
    // Intentar obtener el último comando enviado (priorizar CommandRegistry)
    String? lastCommand;
    if (resolved != null) {
      lastCommand = resolved.rawCommand;
    } else {
      lastCommand = _lastCommandSent;
    }

    print(
        '🔍 [$timeStr] lastCommand: "$lastCommand", line: "$line", contains[]: ${line.contains('[')}');

    // Procesar respuestas de comandos de información del dispositivo
    if (lastCommand != null && line.isNotEmpty) {
      print('✅ [$timeStr] Procesando comando de info: $lastCommand');
      // Nota: Algunas respuestas de info vienen entre corchetes ej. "[401474680066]".
      // No filtrar por patrón de peso aquí; dejamos que cada caso procese su respuesta.
      // Algunas básculas devuelven la respuesta entre corchetes, ej: "[401474680066]"
      final cleaned = (line.startsWith('[') && line.endsWith(']'))
          ? line.substring(1, line.length - 1).trim()
          : line.trim();

      // Comando {TTCSER} - Número de serie
      if (lastCommand == '{TTCSER}') {
        print('📋 [$timeStr] NÚMERO DE SERIE RECIBIDO: "$cleaned"');
        emit(s.copyWith(serialNumber: cleaned));
        _lastCommandSent = null; // Limpiar tracking
        _unlockNextCommand();
        return;
      }

      // Comando {VA} - Versión de firmware
      if (lastCommand == '{VA}') {
        print('🔧 [$timeStr] VERSIÓN DE FIRMWARE RECIBIDA: "$cleaned"');
        emit(s.copyWith(firmwareVersion: cleaned));
        _lastCommandSent = null; // Limpiar tracking
        _unlockNextCommand();
        return;
      }

      // Comando {SACC} - Código de celda
      if (lastCommand == '{SACC}') {
        print('🏷️ [$timeStr] CÓDIGO DE CELDA RECIBIDO: "$cleaned"');
        emit(s.copyWith(cellCode: cleaned));
        _lastCommandSent = null; // Limpiar tracking
        _unlockNextCommand();
        return;
      }

      // Comando {SCLS} - Especificaciones de celda.
      // Requisito actual: usar el MISMO valor numérico para ambos campos:
      //  - `cellLoadmVV` con sufijo ' mV/V'
      //  - `microvoltsPerDivision` sin unidad (solo número)
      if (lastCommand == '{SCLS}') {
        print('⚡ [$timeStr] ESPECIFICACIONES DE CELDA RECIBIDAS: "$cleaned"');
        // Parseo: separar por espacio o coma y tomar el primer token numérico.
        final parts = cleaned
            .split(RegExp(r'[\s,]+'))
            .where((p) => p.isNotEmpty)
            .toList();
        String? rawValue;
        if (parts.isNotEmpty) {
          // Aceptar primer elemento como valor base.
          rawValue = parts[0];
        }
        if (rawValue != null) {
          // Normalizar posible símbolo unitario incluido (ej: "2.0mV/V" o "2.0μV/div")
          final normalized = rawValue
              .replaceAll(
                  RegExp(r'(mV\/V|μV\/div|uV\/div|mV|μV|uV)',
                      caseSensitive: false),
                  '')
              .trim();
          emit(s.copyWith(
            cellLoadmVV: '$normalized mV/V',
            microvoltsPerDivision: normalized, // sin unidad
          ));
        } else {
          print(
              '⚠️ [$timeStr] No se pudo extraer valor base de SCLS: "$cleaned"');
        }
        _lastCommandSent = null; // Limpiar tracking
        _unlockNextCommand();
        return;
      }

      // Comando {SCZERO} - Confirmación de reset
      if (lastCommand == '{SCZERO}') {
        print('0️⃣ [$timeStr] CONFIRMACIÓN ZERO RECIBIDA: "$cleaned"');
        _lastCommandSent = null; // Limpiar tracking
        _unlockNextCommand();
        return;
      }

      // Comando {SCAV} - Ruido CAD (conversor analógico-digital)
      if (lastCommand == '{SCAV}') {
        print('📡 [$timeStr] RUIDO CAD RECIBIDO: "$cleaned"');
        emit(s.copyWith(adcNoise: cleaned));
        _lastCommandSent = null; // Limpiar tracking
        _unlockNextCommand();
        return;
      }
    }

    // OPTIMIZACIÓN: Procesar solo datos de peso para máxima velocidad
    // Detectar formato [valor], [Uvalor] o [-valor] - PESO PRIORITARIO
    // ⚠️ SOLO procesar como peso si el último comando fue relacionado con peso
    final weightRegex = RegExp(r'\[(U?-?\d+\.?\d*\s*)\]');
    final weightMatch = weightRegex.firstMatch(line);

    if (weightMatch != null && !_pollingSuspended) {
      // ✅ Procesar valores numéricos si el comando fue {RW}, {BV}, {BC}
      // Nota: ya NO procesamos cuando lastCommand is null para evitar ruido durante otras operaciones
      final isDataCommand = lastCommand == '{RW}' ||
          lastCommand == '{BV}' ||
          lastCommand == '{BC}';

      if (!isDataCommand) {
        print(
            '⏭️ [$timeStr] Ignorando valor [$line] - comando actual: $lastCommand (no es comando de datos)');
        // No desbloquear aquí: seguimos esperando la respuesta real del comando en curso
        return;
      }

      final fullValueStr =
          (weightMatch.group(1) ?? '').trim(); // Remover espacios
      double? value;
      WeightStatus status = WeightStatus.stable;

      print(
          '🔍 Valor extraído: "$fullValueStr" (original: "${weightMatch.group(1)}")');

      if (fullValueStr.startsWith('U')) {
        status = WeightStatus.unstable;
        value = double.tryParse(fullValueStr.substring(1).trim());
        print('📊 Detectado PESO INESTABLE: $value kg');
      } else if (fullValueStr.startsWith('-')) {
        status = WeightStatus.negative;
        value = double.tryParse(fullValueStr.trim());
        print('📊 Detectado PESO NEGATIVO: $value kg');
      } else {
        status = WeightStatus.stable;
        value = double.tryParse(fullValueStr.trim());
        print('📊 Detectado PESO ESTABLE: $value kg');
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
    // Evitar actualizar peso cuando el polling está suspendido (página de info)
    if (!_pollingSuspended) {
      final kg = extractFirstNumber(line);
      if (kg != null) {
        emit(s.copyWith(
            weight: WeightReading(
                kg: kg, at: DateTime.now(), status: WeightStatus.stable)));
      }
    }

    // Importante: No desbloquear aquí incondicionalmente.
    // El desbloqueo solo debe ocurrir cuando procesamos una respuesta
    // correspondiente al comando esperado o por timeout de seguridad.
  }

  /// 🔄 Desbloquea el envío del siguiente comando en la secuencia
  void _unlockNextCommand() {
    if (_pollingSuspended) {
      // Si está suspendido, no programar siguiente comando
      return;
    }
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
  void _sendNextSequentialCommand({String? forceCommand}) {
    if (_pollingSuspended) {
      print('⏸️ Polling suspendido → no se envía comando automático');
      return;
    }
    if (_waitingForResponse) return; // Ya hay un comando pendiente

    String nextCommand;

    // 🚀 SECUENCIA INICIAL: Comandos específicos al inicio
    if (_isInitialSequence) {
      final initialCommands = ['{RW}', '{BV}', '{BC}'];

      if (_initialSequenceStep < initialCommands.length) {
        nextCommand = initialCommands[_initialSequenceStep];
        _initialSequenceStep++;

        print('🚀 Secuencia inicial ($_initialSequenceStep/3): $nextCommand');

        // Si completamos la secuencia inicial, cambiar a modo normal
        if (_initialSequenceStep >= initialCommands.length) {
          _isInitialSequence = false;
          print('✅ Secuencia inicial completada → Modo polling normal');
        }

        // Actualizar contadores
        if (nextCommand == '{RW}') {
          _weightRequestCount++;
        } else {
          _batteryRequestCount++;
          _lastBatteryRequest = DateTime.now();
        }
      } else {
        // Fallback a modo normal si algo falla
        _isInitialSequence = false;
        nextCommand = '{RW}';
        _weightRequestCount++;
      }
    }
    // 🚀 COMANDO FORZADO: Para casos especiales
    else if (forceCommand != null) {
      nextCommand = forceCommand;
      print('🎯 Comando forzado: $nextCommand');

      // Actualizar contadores según el tipo
      if (nextCommand == '{RW}') {
        _weightRequestCount++;
      } else if (nextCommand == '{BV}' || nextCommand == '{BC}') {
        _batteryRequestCount++;
        _lastBatteryRequest = DateTime.now();
      }
    }
    // �🏆 PRIORIDAD AL PESO: Siempre enviar {RW} a menos que sea tiempo de batería
    else if (_shouldRequestBattery()) {
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

      // 🛡️ TIMEOUT DE SEGURIDAD: Variable según tipo de comando
      // Comandos de información del dispositivo necesitan más tiempo
      final isDeviceInfoCommand = e.command == '{TTCSER}' ||
          e.command == '{VA}' ||
          e.command == '{SACC}' ||
          e.command == '{SCLS}';

      final timeoutDuration = isDeviceInfoCommand
          ? const Duration(seconds: 3) // Más tiempo para info del dispositivo
          : const Duration(milliseconds: 500); // Rápido para peso/batería

      _responseTimeoutTimer?.cancel();
      _responseTimeoutTimer = Timer(timeoutDuration, () {
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

    if (_pollingSuspended) {
      print('▶️ Reanudando polling (estaba suspendido)');
    }
    _pollingSuspended = false;

    print('🎯 === INICIANDO POLLING OPTIMIZADO (PESO PRIORITARIO) ===');
    print('📋 Sistema: Secuencial con tracking completo');
    print('📋 Prioridad: {RW} (continuo) + {BV}/{BC} (cada 1 minuto)');

    // 🔄 NUEVO SISTEMA: Polling optimizado con prioridad al peso
    // Solo envía el primer comando, los siguientes se envían cuando llega respuesta

    // Reiniciar estado para polling limpio
    _waitingForResponse = false;
    _responseTimeoutTimer?.cancel();
    _responseTimeoutTimer = null;

    // 🚀 ACTIVAR SECUENCIA INICIAL: Peso + Batería completa
    _isInitialSequence = true;
    _initialSequenceStep = 0;
    _weightRequestCount = 0;
    _batteryRequestCount = 0;

    print('� Activando secuencia inicial: {RW} → {BV} → {BC}');

    // 🚀 SECUENCIA INICIAL: Pedir datos completos al iniciar
    print('📤 Iniciando secuencia inicial completa con tracking...');

    // Iniciar con la secuencia de comandos iniciales
    _sendNextSequentialCommand(); // Los siguientes comandos se enviarán automáticamente por el sistema secuencial
    // cuando lleguen las respuestas correspondientes
  }

  Future<void> _onStopPolling(
      StopPolling e, Emitter<ConnectionState> emit) async {
    print('🛑 === DETENIENDO POLLING ===');

    _pollTimer?.cancel();
    _pollTimer = null;
    _responseTimeoutTimer?.cancel();
    _responseTimeoutTimer = null;
    _waitingForResponse = false;
    _pollingSuspended = true;

    print('🛑 Polling secuencial detenido - Timer cancelado');
    print('🛑 No se enviarán más comandos automáticos de peso');
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

    // 1. Cancelar todos los timers
    _pollTimer?.cancel();
    _responseTimeoutTimer?.cancel();

    // 2. Cancelar suscripción al stream
    await _sub?.cancel();

    // 3. Desconectar dispositivo si está conectado
    try {
      final isConnected = await repo.isConnected();
      if (isConnected) {
        print('🔌 Desconectando dispositivo antes de cerrar bloc...');
        await repo.disconnect();
      }
    } catch (error) {
      print('⚠️ Error al desconectar durante close: $error');
    }

    // 4. Limpiar CommandRegistry
    _commandRegistry.purgeTimeouts();

    print('✅ ConnectionBloc cerrado correctamente');
    return super.close();
  }
}

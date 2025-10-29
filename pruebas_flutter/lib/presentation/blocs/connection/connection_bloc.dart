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
      for (int i = 0; i < 3; i++) {
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

        // Volver a comandos separados con mejor control
        print('🚀 Solicitando peso inicial...');
        add(SendCommandRequested('{RW}'));
        await Future.delayed(const Duration(milliseconds: 800));
        print('🔋 Solicitando voltaje inicial...');
        add(SendCommandRequested('{BV}'));
        await Future.delayed(const Duration(milliseconds: 800));
        print('🔋 Solicitando porcentaje inicial...');
        add(SendCommandRequested('{BC}'));

        await Future.delayed(const Duration(milliseconds: 1000));
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

    print('📥 DATOS RECIBIDOS: "$line"');

    if (line == '__DISCONNECTED__') {
      emit(const ConnectionState.disconnected());
      return;
    }

    // Detectar formato específico de Tru-Test S3: "88|7.95|3.308|1.02|09:31:44.340"
    final s3Regex = RegExp(r'^\d+\|(\d+\.?\d*)\|[\d\.]+\|[\d\.]+\|[\d:\.]+$');
    final s3Match = s3Regex.firstMatch(line);

    if (s3Match != null) {
      final weightStr = s3Match.group(1);
      final weight = double.tryParse(weightStr ?? '');
      if (weight != null) {
        print('⚖️ PESO S3 detectado: ${weight}kg');
        emit(s.copyWith(
            weight: WeightReading(
                kg: weight, at: DateTime.now(), status: WeightStatus.stable)));
        return;
      }
    }

    // Detectar datos en formato [valor], [Uvalor] o [-valor]
    final weightRegex = RegExp(r'\[(U?-?\d+\.?\d*)\]');
    final weightMatch = weightRegex.firstMatch(line);

    if (weightMatch != null) {
      final fullValueStr = weightMatch.group(1) ?? '';
      double? value;
      WeightStatus status = WeightStatus.stable;

      if (fullValueStr.startsWith('U')) {
        // Peso inestable [U0.5]
        status = WeightStatus.unstable;
        value = double.tryParse(fullValueStr.substring(1));
        print('⚖️ PESO INESTABLE detectado: $value kg');
      } else if (fullValueStr.startsWith('-')) {
        // Peso negativo [-0.5]
        status = WeightStatus.negative;
        value = double.tryParse(fullValueStr);
        print('⚖️ PESO NEGATIVO detectado: $value kg');
      } else {
        // Peso estable [0.5]
        status = WeightStatus.stable;
        value = double.tryParse(fullValueStr);
        print('⚖️ PESO ESTABLE detectado: $value kg');
      }

      if (value != null) {
        print('🔍 Valor detectado: $value (${status.name})');

        // NUEVA LÓGICA: Interpretar basado en rangos de valores típicos
        // En lugar de usar secuencia, usar heurística de rangos

        if (value >= 1.0 && value <= 6.0) {
          // Rango típico de voltaje de batería (1V - 6V)
          print('🔋 INTERPRETADO COMO VOLTAJE (rango): ${value}V');
          emit(s.copyWith(
              batteryVoltage: BatteryStatus(volts: value, at: DateTime.now())));
        } else if (value >= 0 && value <= 100 && value % 1 == 0) {
          // Rango típico de porcentaje (0% - 100%) y es número entero
          print('🔋 INTERPRETADO COMO PORCENTAJE (rango): ${value}%');
          emit(s.copyWith(
              batteryPercent:
                  BatteryStatus(percent: value, at: DateTime.now())));
        } else {
          // Cualquier otro valor se interpreta como peso
          print(
              '⚖️ INTERPRETADO COMO PESO (rango): ${value}kg - ${status.name}');
          emit(s.copyWith(
              weight: WeightReading(
                  kg: value, at: DateTime.now(), status: status)));
        }
        return;
      }
    }

    // Fallback: intentar extraer cualquier número como peso
    final kg = extractFirstNumber(line);
    if (kg != null) {
      print('⚖️ PESO GENÉRICO: ${kg}kg');
      emit(s.copyWith(
          weight: WeightReading(
              kg: kg, at: DateTime.now(), status: WeightStatus.stable)));
    } else {
      print('❓ LÍNEA NO RECONOCIDA: "$line"');
    }
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

      // Registrar comandos en la secuencia esperada
      if (e.command == '{RW}' || e.command == '{BV}' || e.command == '{BC}') {
        print('📝 Comando ${e.command} enviado');
        // No necesitamos historial, usamos la secuencia predefinida
      }

      await repo.sendCommand(e.command);
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

    int tick = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      tick++;

      // Reiniciar secuencia cada ciclo completo
      if (tick % 3 == 1) {
        print('📊 Polling: Solicitando peso...');
        add(SendCommandRequested('{RW}'));
      } else if (tick % 3 == 2) {
        print('🔋 Polling: Solicitando voltaje...');
        add(SendCommandRequested('{BV}'));
      } else if (tick % 3 == 0) {
        print('🔋 Polling: Solicitando porcentaje...');
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
    return super.close();
  }
}

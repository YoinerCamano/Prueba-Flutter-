import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/number_parsing.dart';
import '../../../domain/bluetooth_repository.dart';
import '../../../domain/entities.dart';
import '../../../data/datasources/command_registry.dart';

part 'device_info_event.dart';
part 'device_info_state.dart';

/// BLoC dedicado a datos técnicos (no peso).
/// Separa el flujo de comandos para evitar cruce con el pesaje.
class DeviceInfoBloc extends Bloc<DeviceInfoEvent, DeviceInfoState> {
  final BluetoothRepository repo;
  final CommandRegistry _commandRegistry;
  StreamSubscription<String>? _sub;

  String? _lastCommandSent;
  bool _waitingForResponse = false;
  Timer? _responseTimeoutTimer;
  final List<String> _pendingQueue = [];
  String? _pendingFragment; // Para manejar respuestas partidas (EziWeigh7)

  DeviceInfoBloc(this.repo, this._commandRegistry)
      : super(const DeviceInfoState()) {
    on<DeviceInfoStartListening>(_onStartListening);
    on<DeviceInfoStopListening>(_onStopListening);
    on<DeviceInfoSendCommandRequested>(_onSendCommand);
    on<DeviceInfoRawLineArrived>(_onRawLine);
  }

  Future<void> _onStartListening(
      DeviceInfoStartListening event, Emitter<DeviceInfoState> emit) async {
    await _sub?.cancel();
    _waitingForResponse = false;
    _responseTimeoutTimer?.cancel();
    _responseTimeoutTimer = null;

    _sub = repo.rawStream().listen((line) {
      add(DeviceInfoRawLineArrived(line));
    }, onError: (error) {
      add(DeviceInfoRawLineArrived('__ERROR__: $error'));
    }, onDone: () {
      add(DeviceInfoRawLineArrived('__DISCONNECTED__'));
    });
  }

  Future<void> _onStopListening(
      DeviceInfoStopListening event, Emitter<DeviceInfoState> emit) async {
    await _sub?.cancel();
    _sub = null;
    _waitingForResponse = false;
    _responseTimeoutTimer?.cancel();
    _responseTimeoutTimer = null;
  }

  Future<void> _onSendCommand(
      DeviceInfoSendCommandRequested e, Emitter<DeviceInfoState> emit) async {
    // Evitar cruce: si estamos esperando respuesta, encolar
    if (_waitingForResponse) {
      _pendingQueue.add(e.command);
      print(
          '📦 DeviceInfoBloc: Comando ${e.command} encolado (esperando respuesta previa)');
      return;
    }

    // Solo comandos técnicos y batería.
    _lastCommandSent = e.command;
    _waitingForResponse = true;
    _commandRegistry.registerOutgoing(e.command);

    print('📤 DeviceInfoBloc: Enviando comando ${e.command}...');

    // Timeout prudente para info técnica.
    _responseTimeoutTimer?.cancel();
    _responseTimeoutTimer = Timer(const Duration(milliseconds: 500), () {
      if (_waitingForResponse) {
        print('⏰ DeviceInfoBloc: Timeout esperando respuesta de ${e.command}');
        _waitingForResponse = false;
        _sendNextFromQueue();
      }
    });

    await repo.sendCommand(e.command);
  }

  void _sendNextFromQueue() {
    if (_pendingQueue.isEmpty || _waitingForResponse) return;
    final next = _pendingQueue.removeAt(0);
    add(DeviceInfoSendCommandRequested(next));
  }

  Future<void> _onRawLine(
      DeviceInfoRawLineArrived e, Emitter<DeviceInfoState> emit) async {
    var line = e.line.trim();
    if (line.isEmpty || line == '__DISCONNECTED__') {
      return;
    }
    if (line.startsWith('__ERROR__')) {
      return;
    }

    // 🔧 Manejo de fragmentos partidos (EziWeigh7)
    // Si la línea empieza con [ pero no termina con ], guardar fragmento
    if (line.startsWith('[') && !line.contains(']')) {
      _pendingFragment = line;
      print('🧩 DeviceInfoBloc: Fragmento inicial guardado: "$line"');
      return;
    }

    // Si tenemos un fragmento pendiente y llega el final
    if (_pendingFragment != null && line.contains(']')) {
      line = (_pendingFragment! + line).replaceAll(RegExp(r'\s+'), '');
      _pendingFragment = null;
      print('✅ DeviceInfoBloc: Fragmentos ensamblados: "$line"');
    }

    final lastCommand = _lastCommandSent;
    print(
        '📥 DeviceInfoBloc._onRawLine: lastCommand=$lastCommand, line="$line"');

    // Si no tenemos comando previo o el comando previo no es técnico, ignorar
    if (lastCommand == null || !_isTechnicalCommand(lastCommand)) {
      print('⚠️ Ignorando línea: comando no técnico o null');
      return;
    }

    final cleaned = (line.startsWith('[') && line.endsWith(']'))
        ? line.substring(1, line.length - 1).trim()
        : line.trim();
    print('🧹 DeviceInfoBloc: cleaned="$cleaned"');

    // Datos numéricos (voltaje / porcentaje)
    final number = extractFirstNumber(cleaned);
    print('🔢 DeviceInfoBloc: número extraído = $number');

    if (number != null) {
      if (lastCommand == '{BV}' && number > 0 && number <= 20) {
        print('🔋 DeviceInfoBloc: Asignando voltaje = $number V');
        _waitingForResponse = false;
        _responseTimeoutTimer?.cancel();
        emit(state.copyWith(
            batteryVoltage: BatteryStatus(volts: number, at: DateTime.now())));
        _sendNextFromQueue();
        return;
      }
      if (lastCommand == '{BC}' && number >= 0 && number <= 110) {
        print('🔋 DeviceInfoBloc: Asignando porcentaje = $number %');
        _waitingForResponse = false;
        _responseTimeoutTimer?.cancel();
        emit(state.copyWith(
            batteryPercent:
                BatteryStatus(percent: number, at: DateTime.now())));
        _sendNextFromQueue();
        return;
      }
    }

    // Log si no se reconoce el número de batería
    if (lastCommand == '{BV}' || lastCommand == '{BC}') {
      print(
          '⚠️ DeviceInfoBloc: Comando $lastCommand con valor "$cleaned" (number=$number) NO CUMPLE RANGO');
    }

    // Datos textuales
    if (lastCommand == '{TTCSER}') {
      // Número de serie
      _waitingForResponse = false;
      _responseTimeoutTimer?.cancel();
      // Validar > 100,000
      final digitsOnly = RegExp(r'\d+').firstMatch(cleaned)?.group(0);
      if (digitsOnly != null) {
        final value = int.tryParse(digitsOnly);
        if (value != null && value > 100000) {
          print('📋 DeviceInfoBloc: Número de serie válido = $cleaned');
          emit(state.copyWith(serialNumber: cleaned));
        } else {
          print(
              '⚠️ DeviceInfoBloc: Serial rechazado (${value ?? 'no numérico'}): $cleaned');
        }
      }
      _sendNextFromQueue();
      return;
    }
    if (lastCommand == '{VA}') {
      if (_isWeightNoise(cleaned)) {
        return;
      }
      _waitingForResponse = false;
      _responseTimeoutTimer?.cancel();
      emit(state.copyWith(firmwareVersion: cleaned));
      _sendNextFromQueue();
      return;
    }
    if (lastCommand == '{SCLS}') {
      print('🔍 DeviceInfoBloc: Procesando {SCLS}...');
      _waitingForResponse = false;
      _responseTimeoutTimer?.cancel();
      final parts =
          cleaned.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).toList();
      final rawValue = parts.isNotEmpty ? parts[0] : cleaned;
      final normalized = rawValue
          .replaceAll(
              RegExp(r'(mV\/V|μV\/div|uV\/div|mV|μV|uV)', caseSensitive: false),
              '')
          .trim();
      print('⚡ DeviceInfoBloc: Emitiendo cellLoadmVV = "$normalized mV/V"');
      emit(state.copyWith(
        cellLoadmVV: '$normalized mV/V',
      ));
      _sendNextFromQueue();
      return;
    }
    if (lastCommand == '{SCMV}') {
      _waitingForResponse = false;
      _responseTimeoutTimer?.cancel();
      final normalized = cleaned
          .replaceAll(
              RegExp(r'(μV\/div|uV\/div|μV|uV)', caseSensitive: false), '')
          .trim();
      print(
          '🎚️ DeviceInfoBloc: Emitiendo microvoltsPerDivision = "$normalized"');
      emit(state.copyWith(microvoltsPerDivision: normalized));
      _sendNextFromQueue();
      return;
    }
  }

  bool _isWeightNoise(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;

    if (trimmed == '[---]') return true;
    if (RegExp(r'^\[\s*[Uu]').hasMatch(trimmed)) return true;
    if (RegExp(r'^[Uu]').hasMatch(trimmed)) return true;
    return false;
  }

  bool _isTechnicalCommand(String cmd) {
    return cmd == '{TTCSER}' ||
        cmd == '{VA}' ||
        cmd == '{SCLS}' ||
        cmd == '{SCMV}' ||
        cmd == '{BV}' ||
        cmd == '{BC}';
  }
}

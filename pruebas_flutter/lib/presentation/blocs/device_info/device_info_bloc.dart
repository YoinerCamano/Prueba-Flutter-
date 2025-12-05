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
    final line = e.line.trim();
    if (line.isEmpty || line == '__DISCONNECTED__') {
      return;
    }
    if (line.startsWith('__ERROR__')) {
      return;
    }

    final lastCommand = _lastCommandSent;
    // Si no tenemos comando previo o el comando previo no es técnico, ignorar
    if (lastCommand == null || !_isTechnicalCommand(lastCommand)) {
      return;
    }

    final cleaned = (line.startsWith('[') && line.endsWith(']'))
        ? line.substring(1, line.length - 1).trim()
        : line.trim();

    // Datos numéricos (voltaje / porcentaje)
    final number = extractFirstNumber(cleaned);
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
      // Validar que el valor no sea un peso (serial debe ser > 1,000,000 si es numérico)
      final isPureNumeric = RegExp(r'^\d+(?:[\.,]\d+)?$').hasMatch(cleaned);
      final serialNumberCandidate =
          isPureNumeric ? extractFirstNumber(cleaned) : null;
      final likelyWeight =
          (serialNumberCandidate != null && serialNumberCandidate < 1000000) ||
              _looksLikeWeightReading(cleaned);
      if (likelyWeight) {
        return; // Ignorar peso infiltrado
      }
      _waitingForResponse = false;
      _responseTimeoutTimer?.cancel();
      emit(state.copyWith(serialNumber: cleaned));
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
    if (lastCommand == '{SACC}') {
      if (_looksLikeWeightReading(cleaned)) {
        return;
      }
      _waitingForResponse = false;
      _responseTimeoutTimer?.cancel();
      emit(state.copyWith(cellCode: cleaned));
      _sendNextFromQueue();
      return;
    }
    if (lastCommand == '{SCLS}') {
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
      emit(state.copyWith(microvoltsPerDivision: normalized));
      _sendNextFromQueue();
      return;
    }
    if (lastCommand == '{SCAV}') {
      _waitingForResponse = false;
      _responseTimeoutTimer?.cancel();
      emit(state.copyWith(adcNoise: cleaned));
      _sendNextFromQueue();
      return;
    }
  }

  bool _looksLikeWeightReading(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;

    // Patrones típicos de peso: [123.4], [U1.2], U1.2
    final weightBracket = RegExp(r'^\[\s*[Uu-]?\d+(?:[\.,]\d+)?\s*\]$');
    final weightUnstable = RegExp(r'^[Uu]\d+(?:[\.,]\d+)?$');

    if (weightBracket.hasMatch(trimmed) || weightUnstable.hasMatch(trimmed)) {
      return true;
    }
    return false;
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
        cmd == '{SACC}' ||
        cmd == '{SCLS}' ||
        cmd == '{SCMV}' ||
        cmd == '{SCAV}' ||
        cmd == '{BV}' ||
        cmd == '{BC}';
  }
}

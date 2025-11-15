import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/firebase/firebase_service.dart';
import '../connection/connection_bloc.dart';
import '../../../domain/entities.dart';

/// Cubit para manejar la persistencia de mediciones en Firebase
class MeasurementPersistenceCubit extends Cubit<MeasurementPersistenceState> {
  final FirebaseService _firebaseService;
  final ConnectionBloc _connectionBloc;
  String? _currentSessionId;

  MeasurementPersistenceCubit(this._firebaseService, this._connectionBloc)
      : super(MeasurementPersistenceState.initial()) {
    // Escuchar cambios en el ConnectionBloc
    _connectionBloc.stream.listen(_onConnectionStateChanged);

    // Cargar contador inicial
    _loadInitialCount();
  }

  Future<void> _loadInitialCount() async {
    try {
      // El contador se maneja localmente en esta sesión
    } catch (e) {
      print('Error inicializando: $e');
    }
  }

  void _onConnectionStateChanged(ConnectionState state) {
    if (state is Connected && state.weight != null) {
      _saveWeightReading(state);
    }
  }

  /// Inicia una nueva sesión de mediciones
  Future<void> startSession({String? deviceId, String? animalId}) async {
    try {
      emit(state.copyWith(status: PersistenceStatus.saving));

      final sessionId = await _firebaseService.createSession(
        deviceId: deviceId ?? 'unknown',
        animalId: animalId,
        metadata: {'startedAt': DateTime.now().toIso8601String()},
      );

      _currentSessionId = sessionId;
      emit(state.copyWith(
        status: PersistenceStatus.success,
        currentSessionId: sessionId,
      ));

      print('📝 Sesión iniciada: $sessionId');
    } catch (e) {
      emit(state.copyWith(
        status: PersistenceStatus.error,
        errorMessage: 'Error iniciando sesión: $e',
      ));
      print('❌ Error iniciando sesión: $e');
    }
  }

  /// Finaliza la sesión actual
  Future<void> endSession() async {
    if (_currentSessionId == null) return;

    try {
      emit(state.copyWith(status: PersistenceStatus.saving));

      await _firebaseService.endSession(_currentSessionId!);

      emit(state.copyWith(
        status: PersistenceStatus.success,
        currentSessionId: null,
      ));

      print('✅ Sesión finalizada: $_currentSessionId');
      _currentSessionId = null;
    } catch (e) {
      emit(state.copyWith(
        status: PersistenceStatus.error,
        errorMessage: 'Error finalizando sesión: $e',
      ));
      print('❌ Error finalizando sesión: $e');
    }
  }

  /// Guarda una lectura de peso automáticamente
  Future<void> _saveWeightReading(Connected state) async {
    // Guardar solo lecturas válidas y estables cuando el autosave está habilitado
    if (state.weight?.kg == null || !this.state.autoSaveEnabled) return;
    if (state.weight!.status != WeightStatus.stable) return;

    try {
      final measurementId = await _firebaseService.saveMeasurement(
        deviceId: state.device.id,
        weight: state.weight!.kg!,
        unit: 'kg',
        sessionId: _currentSessionId,
        metadata: {
          'status': state.weight!.status.toString(),
          'timestamp': state.weight!.at.toIso8601String(),
          'batteryPercent': state.batteryPercent?.percent,
          'batteryVoltage': state.batteryVoltage?.volts,
        },
      );

      // Actualizar contador de la sesión si existe
      if (_currentSessionId != null) {
        await _firebaseService.incrementSessionMeasurements(_currentSessionId!);
      }

      emit(this.state.copyWith(
            lastSavedMeasurementId: measurementId,
            savedMeasurementsCount: this.state.savedMeasurementsCount + 1,
          ));

      print(
          '💾 Medición guardada: ${state.weight!.kg} kg (ID: $measurementId)');
    } catch (e) {
      print('❌ Error guardando medición: $e');
      // No emitimos error aquí para no interrumpir el flujo de mediciones
    }
  }

  /// Habilita/deshabilita el guardado automático
  void toggleAutoSave() {
    emit(state.copyWith(autoSaveEnabled: !state.autoSaveEnabled));
  }

  /// Guarda inmediatamente la lectura actual del peso.
  /// Solo permite guardar si la lectura es estable.
  /// Retorna true si guardó exitosamente, false si no cumple condiciones.
  Future<bool> saveNow() async {
    final s = _connectionBloc.state;
    if (s is! Connected) return false;

    final reading = s.weight;
    if (reading?.kg == null) return false;

    // CONDICIÓN OBLIGATORIA: Solo guardar si está estable
    if (reading!.status != WeightStatus.stable) {
      print('⚠️ Guardado rechazado: peso no estable (${reading.status})');
      return false;
    }

    try {
      final measurementId = await _firebaseService.saveMeasurement(
        deviceId: s.device.id,
        weight: reading.kg!,
        unit: 'kg',
        sessionId: null,
        metadata: {},
      );

      // Incrementar contador inmediatamente
      final newCount = state.savedMeasurementsCount + 1;
      emit(state.copyWith(
        lastSavedMeasurementId: measurementId,
        savedMeasurementsCount: newCount,
        status: PersistenceStatus.success,
      ));

      print('💾 Guardado: ${reading.kg} kg (#$newCount, ID: $measurementId)');
      return true;
    } catch (e) {
      print('❌ Error guardando: $e');
      emit(state.copyWith(status: PersistenceStatus.error));
      return false;
    }
  }
}

/// Estados de la persistencia
enum PersistenceStatus { initial, saving, success, error }

/// Estado del cubit de persistencia
class MeasurementPersistenceState {
  final PersistenceStatus status;
  final String? currentSessionId;
  final String? errorMessage;
  final bool autoSaveEnabled;
  final int savedMeasurementsCount;
  final String? lastSavedMeasurementId;

  MeasurementPersistenceState({
    required this.status,
    this.currentSessionId,
    this.errorMessage,
    this.autoSaveEnabled = true,
    this.savedMeasurementsCount = 0,
    this.lastSavedMeasurementId,
  });

  factory MeasurementPersistenceState.initial() {
    return MeasurementPersistenceState(
      status: PersistenceStatus.initial,
      autoSaveEnabled: false, // Guardado manual únicamente
    );
  }

  MeasurementPersistenceState copyWith({
    PersistenceStatus? status,
    String? currentSessionId,
    String? errorMessage,
    bool? autoSaveEnabled,
    int? savedMeasurementsCount,
    String? lastSavedMeasurementId,
  }) {
    return MeasurementPersistenceState(
      status: status ?? this.status,
      currentSessionId: currentSessionId ?? this.currentSessionId,
      errorMessage: errorMessage ?? this.errorMessage,
      autoSaveEnabled: autoSaveEnabled ?? this.autoSaveEnabled,
      savedMeasurementsCount:
          savedMeasurementsCount ?? this.savedMeasurementsCount,
      lastSavedMeasurementId:
          lastSavedMeasurementId ?? this.lastSavedMeasurementId,
    );
  }
}

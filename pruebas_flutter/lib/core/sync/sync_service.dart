import 'dart:async';

import 'api_sync_upload_adapter.dart';
import '../../data/local/database_service.dart';
import 'connectivity_service.dart';
import 'sync_config.dart';

/// Estado de una operación de sincronización.
enum SyncStatus { idle, syncing, success, error }

/// Resultado de una operación de sincronización.
class SyncResult {
  final SyncStatus status;
  final int syncedCount;
  final DateTime? lastSyncAt;
  final String? errorMessage;

  const SyncResult({
    required this.status,
    this.syncedCount = 0,
    this.lastSyncAt,
    this.errorMessage,
  });

  static const SyncResult idle = SyncResult(status: SyncStatus.idle);
}

/// Contrato que deben cumplir los adaptadores de subida a la nube.
/// Permite sustituir el backend (Firebase, REST, etc.) sin tocar el servicio.
abstract class SyncUploadAdapter {
  /// Sube los registros al backend.
  /// Devuelve la lista de IDs que se subieron con éxito.
  Future<List<int>> upload(List<Map<String, dynamic>> records);
}

/// Adaptador stub (no-op) cuando no hay backend configurado.
/// Marca todos los registros como sincronizados directamente.
/// Servicio principal de sincronización.
///
/// Responsabilidades:
/// - Leer configuración de [SyncConfigRepository]
/// - Verificar conectividad con [ConnectivityService]
/// - Consultar registros pendientes de [DatabaseService]
/// - Ejecutar la subida mediante un [SyncUploadAdapter]
/// - Registrar la última sincronización exitosa
/// - Gestionar el timer de sincronización automática
class SyncService {
  final DatabaseService _db;
  final ConnectivityService _connectivity;
  final SyncConfigRepository _configRepo;
  final SyncUploadAdapter _uploadAdapter;

  Timer? _timer;
  SyncResult _lastResult = SyncResult.idle;
  DateTime? _lastSuccessAt;
  final _resultController = StreamController<SyncResult>.broadcast();

  SyncService({
    required DatabaseService db,
    ConnectivityService? connectivity,
    SyncConfigRepository? configRepo,
    SyncUploadAdapter? uploadAdapter,
  })  : _db = db,
        _connectivity = connectivity ?? ConnectivityService(),
        _configRepo = configRepo ?? SyncConfigRepository(),
        _uploadAdapter = uploadAdapter ?? ApiSyncUploadAdapter();

  /// Stream de resultados de sincronización.
  Stream<SyncResult> get onSyncResult => _resultController.stream;

  /// Último resultado conocido.
  SyncResult get lastResult => _lastResult;

  /// Fecha/hora de la última sincronización exitosa.
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// Número de registros pendientes de sincronizar.
  Future<int> pendingCount() => _db.countUnsyncedBunches();

  /// Inicializa el servicio: carga config y arranca el timer si procede.
  Future<void> initialize() async {
    _lastSuccessAt = await _configRepo.loadLastSuccessfulSyncAt();
    _lastResult = SyncResult(
      status: SyncStatus.idle,
      lastSyncAt: _lastSuccessAt,
    );
    final config = await _configRepo.load();
    _rescheduleTimer(config);
  }

  /// Reconfigura el timer según la nueva configuración.
  Future<void> updateConfig(SyncConfig config) async {
    await _configRepo.save(config);
    _rescheduleTimer(config);
  }

  void _rescheduleTimer(SyncConfig config) {
    _timer?.cancel();
    _timer = null;
    if (!config.autoSyncEnabled) return;
    _timer = Timer.periodic(config.interval.duration, (_) async {
      final currentConfig = await _configRepo.load();
      await _runSync(currentConfig, manual: false);
    });
  }

  /// Sincronización manual: ignora el intervalo pero respeta conectividad.
  Future<SyncResult> syncNow() async {
    final config = await _configRepo.load();
    return _runSync(config, manual: true);
  }

  Future<SyncResult> _runSync(SyncConfig config, {required bool manual}) async {
    // Verificar que no haya otra sync en curso
    if (_lastResult.status == SyncStatus.syncing) return _lastResult;

    _emit(const SyncResult(status: SyncStatus.syncing));

    try {
      // 1. Verificar conectividad
      final networkType = await _connectivity.currentNetworkType();
      if (networkType == NetworkType.none) {
        return _emitError('Sin conexión a internet');
      }
      if (config.wifiOnly && networkType != NetworkType.wifi) {
        return _emitError('Se requiere conexión WiFi');
      }

      // 2. Consultar registros pendientes
      final pending = await _db.getUnsyncedBunches();
      if (pending.isEmpty) {
        _lastSuccessAt = DateTime.now();
        await _configRepo.saveLastSuccessfulSyncAt(_lastSuccessAt!);
        final result = SyncResult(
          status: SyncStatus.success,
          syncedCount: 0,
          lastSyncAt: _lastSuccessAt,
        );
        _emit(result);
        return result;
      }

      // 3. Ejecutar subida
      final syncedIds = await _uploadAdapter.upload(pending);

      // 4. Marcar como sincronizados en BD local
      if (syncedIds.isNotEmpty) {
        await _db.markBatchAsSynced(syncedIds);
      }

      _lastSuccessAt = DateTime.now();
      await _configRepo.saveLastSuccessfulSyncAt(_lastSuccessAt!);
      final result = SyncResult(
        status: SyncStatus.success,
        syncedCount: syncedIds.length,
        lastSyncAt: _lastSuccessAt,
      );
      _emit(result);
      return result;
    } catch (e) {
      return _emitError(e.toString());
    }
  }

  SyncResult _emitError(String message) {
    final result = SyncResult(
      status: SyncStatus.error,
      errorMessage: message,
      lastSyncAt: _lastSuccessAt,
    );
    _emit(result);
    return result;
  }

  void _emit(SyncResult result) {
    _lastResult = result;
    if (!_resultController.isClosed) _resultController.add(result);
  }

  void dispose() {
    _timer?.cancel();
    _resultController.close();
  }
}

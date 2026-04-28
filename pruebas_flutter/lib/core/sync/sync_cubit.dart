import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'sync_config.dart';
import 'sync_service.dart';

/// Estado del cubit de sincronización.
class SyncState {
  final SyncConfig config;
  final ApiSyncConfig apiConfig;
  final SyncResult syncResult;
  final int pendingCount;
  final bool isLoadingConfig;

  const SyncState({
    required this.config,
    required this.apiConfig,
    required this.syncResult,
    required this.pendingCount,
    this.isLoadingConfig = false,
  });

  SyncState copyWith({
    SyncConfig? config,
    ApiSyncConfig? apiConfig,
    SyncResult? syncResult,
    int? pendingCount,
    bool? isLoadingConfig,
  }) {
    return SyncState(
      config: config ?? this.config,
      apiConfig: apiConfig ?? this.apiConfig,
      syncResult: syncResult ?? this.syncResult,
      pendingCount: pendingCount ?? this.pendingCount,
      isLoadingConfig: isLoadingConfig ?? this.isLoadingConfig,
    );
  }

  static SyncState initial() => const SyncState(
        config: SyncConfig(),
      apiConfig: ApiSyncConfig(),
        syncResult: SyncResult.idle,
        pendingCount: 0,
        isLoadingConfig: true,
      );
}

/// Cubit que expone el estado de sincronización a la UI.
class SyncCubit extends Cubit<SyncState> {
  final SyncService _service;
  StreamSubscription<SyncResult>? _resultSub;

  SyncCubit(this._service) : super(SyncState.initial()) {
    _resultSub = _service.onSyncResult.listen((result) {
      emit(state.copyWith(syncResult: result));
      // Si terminó exitosamente o con error, actualizar contador de pendientes
      if (result.status == SyncStatus.success ||
          result.status == SyncStatus.error) {
        _refreshPendingCount();
      }
    });
  }

  /// Carga inicial de configuración y datos.
  Future<void> initialize() async {
    emit(state.copyWith(isLoadingConfig: true));
    final repo = SyncConfigRepository();
    await _service.initialize();
    final config = await repo.load();
    final apiConfig = await repo.loadApiConfig();
    final pending = await _pendingCount();
    emit(state.copyWith(
      config: config,
      apiConfig: apiConfig,
      isLoadingConfig: false,
      pendingCount: pending,
      syncResult: _service.lastResult,
    ));
  }

  /// Actualiza un campo de configuración y lo persiste.
  Future<void> updateConfig(SyncConfig config) async {
    emit(state.copyWith(config: config));
    await _service.updateConfig(config);
  }

  Future<void> updateApiConfig(ApiSyncConfig config) async {
    await SyncConfigRepository().saveApiConfig(config);
    emit(state.copyWith(apiConfig: config));
  }

  /// Lanza sincronización manual.
  Future<void> syncNow() async {
    await _service.syncNow();
    await _refreshPendingCount();
  }

  Future<void> _refreshPendingCount() async {
    final count = await _pendingCount();
    emit(state.copyWith(pendingCount: count));
  }

  Future<int> _pendingCount() async {
    try {
      return await _service.pendingCount();
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> close() {
    _resultSub?.cancel();
    return super.close();
  }
}

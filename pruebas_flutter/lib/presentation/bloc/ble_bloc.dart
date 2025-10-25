import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:pruebas_flutter/domain/entities/ble_device.dart';
import 'package:pruebas_flutter/domain/usecases/scan_devices.dart';
import 'package:pruebas_flutter/domain/usecases/connect_device.dart';
import 'package:pruebas_flutter/domain/usecases/disconnect_device.dart';
import 'package:pruebas_flutter/core/permissions/permission_service.dart';

// ----- EVENTS -----
class BleEvent extends Equatable {
  const BleEvent();
  @override
  List<Object?> get props => [];

  factory BleEvent.checkPermissions() = _CheckPermissions;
  factory BleEvent.startScan() = _StartScan;
  factory BleEvent.stopScan() = _StopScan;
  factory BleEvent.connect(String id) = _Connect;
  factory BleEvent.disconnect(String id) = _Disconnect;
  factory BleEvent._devicesUpdated(List<BleDevice> list) = _DevicesUpdated;
  factory BleEvent._error(String message) = _ErrorOccurred;
}

class _CheckPermissions extends BleEvent {}
class _StartScan extends BleEvent {}
class _StopScan extends BleEvent {}
class _Connect extends BleEvent { final String id; const _Connect(this.id); @override List<Object?> get props => [id]; }
class _Disconnect extends BleEvent { final String id; const _Disconnect(this.id); @override List<Object?> get props => [id]; }
class _DevicesUpdated extends BleEvent { final List<BleDevice> list; const _DevicesUpdated(this.list); @override List<Object?> get props => [list]; }
class _ErrorOccurred extends BleEvent { final String message; const _ErrorOccurred(this.message); @override List<Object?> get props => [message]; }

// ----- STATES -----
class BleState extends Equatable {
  final bool permissionsOk;
  final bool scanning;
  final List<BleDevice> devices;
  final String? connectingId;
  final Set<String> connectedIds;
  final String? error;

  const BleState({
    required this.permissionsOk,
    required this.scanning,
    required this.devices,
    required this.connectingId,
    required this.connectedIds,
    required this.error,
  });

  factory BleState.initial() => const BleState(
        permissionsOk: false,
        scanning: false,
        devices: [],
        connectingId: null,
        connectedIds: {},
        error: null,
      );

  BleState copyWith({
    bool? permissionsOk,
    bool? scanning,
    List<BleDevice>? devices,
    String? connectingId,
    Set<String>? connectedIds,
    String? error,
  }) {
    return BleState(
      permissionsOk: permissionsOk ?? this.permissionsOk,
      scanning: scanning ?? this.scanning,
      devices: devices ?? this.devices,
      connectingId: connectingId,
      connectedIds: connectedIds ?? this.connectedIds,
      error: error,
    );
  }

  @override
  List<Object?> get props => [permissionsOk, scanning, devices, connectingId, connectedIds, error];
}

// ----- BLOC -----
class BleBloc extends Bloc<BleEvent, BleState> {
  final ScanDevices scanDevices;
  final ConnectDevice connectDevice;
  final DisconnectDevice disconnectDevice;
  final PermissionService permissionService;

  StreamSubscription<List<BleDevice>>? _scanSub;

  BleBloc({
    required this.scanDevices,
    required this.connectDevice,
    required this.disconnectDevice,
    required this.permissionService,
  }) : super(BleState.initial()) {
    on<_CheckPermissions>(_onCheckPermissions);
    on<_StartScan>(_onStartScan);
    on<_StopScan>(_onStopScan);
    on<_DevicesUpdated>(_onDevicesUpdated);
    on<_Connect>(_onConnect);
    on<_Disconnect>(_onDisconnect);
    on<_ErrorOccurred>(_onError);
  }

  Future<void> _onCheckPermissions(_CheckPermissions event, Emitter<BleState> emit) async {
    final ok = await permissionService.ensureBlePermissions();
    emit(state.copyWith(permissionsOk: ok, error: ok ? null : 'Permisos de Bluetooth/Ubicación no concedidos'));
  }

  Future<void> _onStartScan(_StartScan event, Emitter<BleState> emit) async {
    if (!state.permissionsOk) {
      emit(state.copyWith(error: 'Permisos no concedidos. Ve a ajustes y habilítalos.'));
      return;
    }
    await _scanSub?.cancel();
    emit(state.copyWith(scanning: true, devices: [], error: null));
    _scanSub = scanDevices().listen(
      (list) => add(BleEvent._devicesUpdated(list)),
      onError: (e) => add(BleEvent._error(e.toString())),
      onDone: () => add(BleEvent._error('Escaneo finalizado')),
    );
  }

  Future<void> _onStopScan(_StopScan event, Emitter<BleState> emit) async {
    await _scanSub?.cancel();
    await scanDevices.stop();
    emit(state.copyWith(scanning: false));
  }

  void _onDevicesUpdated(_DevicesUpdated event, Emitter<BleState> emit) {
    emit(state.copyWith(devices: event.list, error: null));
  }

  Future<void> _onConnect(_Connect event, Emitter<BleState> emit) async {
    emit(state.copyWith(connectingId: event.id, error: null));
    try {
      await connectDevice(event.id);
      final newSet = Set<String>.from(state.connectedIds)..add(event.id);
      emit(state.copyWith(connectingId: null, connectedIds: newSet));
    } catch (e) {
      emit(state.copyWith(connectingId: null, error: 'Error conectando: $e'));
    }
  }

  Future<void> _onDisconnect(_Disconnect event, Emitter<BleState> emit) async {
    try {
      await disconnectDevice(event.id);
      final newSet = Set<String>.from(state.connectedIds)..remove(event.id);
      emit(state.copyWith(connectedIds: newSet));
    } catch (e) {
      emit(state.copyWith(error: 'Error al desconectar: $e'));
    }
  }

  void _onError(_ErrorOccurred event, Emitter<BleState> emit) {
    emit(state.copyWith(error: event.message, scanning: false));
  }

  @override
  Future<void> close() async {
    await _scanSub?.cancel();
    return super.close();
  }
}
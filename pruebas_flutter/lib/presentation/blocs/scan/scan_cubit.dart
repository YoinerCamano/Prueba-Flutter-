import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/bluetooth_repository.dart';
import '../../../domain/entities.dart';
import '../../pages/home_page.dart';

part 'scan_state.dart';

class ScanCubit extends Cubit<ScanState> {
  final BluetoothRepository sppRepo;
  final BluetoothRepository bleRepo;
  ScanCubit(this.sppRepo, this.bleRepo) : super(const ScanState.initial());

  BluetoothRepository _repo(TransportMode mode) =>
      mode == TransportMode.spp ? sppRepo : bleRepo;

  Future<void> loadBonded() async {
    print('🔄 === CARGANDO DISPOSITIVOS VINCULADOS ===');
    emit(state.copyWith(loading: true, error: null));

    try {
      final bonded = await sppRepo.bondedDevices();
      print('📊 Dispositivos obtenidos del repositorio: ${bonded.length}');

      for (int i = 0; i < bonded.length; i++) {
        final device = bonded[i];
        print('🔹 [$i] ${device.name} (${device.id})');

        // Verificar S3 específicamente
        if (device.id == 'DE:FD:76:A4:D7:ED' ||
            device.name.contains('S3') ||
            device.name.contains('680066')) {
          print('⚖️  *** S3 DETECTADA EN LISTA UI ***');
        }
      }

      emit(state.copyWith(loading: false, bonded: bonded));
      print('✅ Estado emitido con ${bonded.length} dispositivos');
    } catch (e) {
      print('❌ Error cargando dispositivos vinculados: $e');
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> scan({TransportMode mode = TransportMode.spp}) async {
    print('🔍 === INICIANDO ESCANEO ===');
    print('📡 Modo: ${mode == TransportMode.spp ? 'SPP' : 'BLE'}');

    emit(state.copyWith(scanning: true, error: null));

    try {
      final found = await _repo(mode).scanNearby();
      print('📊 Dispositivos encontrados en escaneo: ${found.length}');

      for (int i = 0; i < found.length; i++) {
        final device = found[i];
        print('🔸 [$i] ${device.name} (${device.id})');
      }

      emit(state.copyWith(scanning: false, found: found));
      print('✅ Escaneo completado');
    } catch (e) {
      print('❌ Error en escaneo: $e');
      emit(state.copyWith(scanning: false, error: e.toString()));
    }
  }
}

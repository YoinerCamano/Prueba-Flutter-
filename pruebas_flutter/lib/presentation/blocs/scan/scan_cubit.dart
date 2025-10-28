import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/bluetooth_repository.dart';
import '../../../domain/entities.dart';

part 'scan_state.dart';

class ScanCubit extends Cubit<ScanState> {
  final BluetoothRepository sppRepo;
  final BluetoothRepository bleRepo;
  ScanCubit(this.sppRepo, this.bleRepo) : super(const ScanState.initial());

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

  /// Escaneo unificado que combina SPP y BLE en un solo proceso
  Future<void> scanUnified() async {
    print('🔍 === INICIANDO ESCANEO UNIFICADO (SPP + BLE) ===');
    print('⏱️ Tiempo total: 30 segundos (15s SPP + 15s BLE)');

    emit(state.copyWith(scanning: true, error: null));

    try {
      final List<BtDevice> allDevices = [];
      final Set<String> deviceIds = {}; // Para evitar duplicados

      // Fase 1: Escaneo SPP (Bluetooth Clásico)
      print('📡 Fase 1: Escaneando dispositivos SPP...');
      try {
        final sppDevices =
            await sppRepo.scanNearby(timeout: const Duration(seconds: 15));
        print('📊 Dispositivos SPP encontrados: ${sppDevices.length}');

        for (final device in sppDevices) {
          if (!deviceIds.contains(device.id)) {
            allDevices.add(device);
            deviceIds.add(device.id);
            print('🔹 SPP: ${device.name} (${device.id})');

            // Verificar S3 específicamente
            if (device.id.toUpperCase().contains('DE:FD:76:A4:D7:ED') ||
                device.name.contains('S3') ||
                device.name.contains('680066')) {
              print('⚖️ *** BÁSCULA S3 ENCONTRADA VIA SPP ***');
            }
          }
        }
      } catch (e) {
        print('❌ Error en escaneo SPP: $e');
      }

      // Pequeña pausa entre escaneos
      await Future.delayed(const Duration(milliseconds: 500));

      // Fase 2: Escaneo BLE
      print('📡 Fase 2: Escaneando dispositivos BLE...');
      try {
        final bleDevices =
            await bleRepo.scanNearby(timeout: const Duration(seconds: 15));
        print('📊 Dispositivos BLE encontrados: ${bleDevices.length}');

        for (final device in bleDevices) {
          if (!deviceIds.contains(device.id)) {
            allDevices.add(device);
            deviceIds.add(device.id);
            print('🔹 BLE: ${device.name} (${device.id})');

            // Verificar S3 específicamente
            if (device.id.toUpperCase().contains('DE:FD:76:A4:D7:ED') ||
                device.name.contains('S3') ||
                device.name.contains('680066')) {
              print('⚖️ *** BÁSCULA S3 ENCONTRADA VIA BLE ***');
            }
          } else {
            print(
                '🔄 Dispositivo ya encontrado por SPP: ${device.name} (${device.id})');
          }
        }
      } catch (e) {
        print('❌ Error en escaneo BLE: $e');
      }

      // Resumen final
      print('📊 === RESUMEN ESCANEO UNIFICADO ===');
      print('🔸 Total dispositivos únicos: ${allDevices.length}');

      // Buscar específicamente la S3
      final s3Devices = allDevices
          .where((d) =>
              d.id.toUpperCase().contains('DE:FD:76:A4:D7:ED') ||
              d.name.contains('S3') ||
              d.name.contains('680066'))
          .toList();

      if (s3Devices.isNotEmpty) {
        print('⚖️ === BÁSCULAS S3 DETECTADAS ===');
        for (int i = 0; i < s3Devices.length; i++) {
          print('⚖️ [$i] ${s3Devices[i].name} (${s3Devices[i].id})');
        }
      } else {
        print('❌ No se encontraron básculas S3');
        print('💡 Consejos:');
        print('   - Asegúrese de que la S3 esté encendida');
        print('   - Mantenga la S3 cerca del dispositivo (< 5 metros)');
        print('   - Verifique que no esté conectada a otro dispositivo');
      }

      emit(state.copyWith(scanning: false, found: allDevices));
      print('✅ Escaneo unificado completado');
    } catch (e) {
      print('❌ Error en escaneo unificado: $e');
      emit(state.copyWith(scanning: false, error: e.toString()));
    }
  }

  /// Detener el escaneo activo
  void stopScanning() {
    if (state.scanning) {
      print('🛑 Deteniendo escaneo activo...');
      emit(state.copyWith(scanning: false));
    }
  }
}

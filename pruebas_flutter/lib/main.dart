import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'data/bluetooth_repository_spp.dart';
import 'data/ble/ble_adapter.dart';
import 'data/ble/bluetooth_repository_ble.dart';
import 'data/datasources/command_registry.dart';
import 'domain/bluetooth_repository.dart';
import 'presentation/blocs/connection/connection_bloc.dart';
import 'presentation/blocs/scan/scan_cubit.dart';
import 'presentation/pages/home_page.dart';
import 'domain/entities.dart';

Future<void> _ensurePermissions() async {
  if (!Platform.isAndroid) return;

  print('=== VERIFICANDO PERMISOS DE BLUETOOTH ===');

  // Solicitar permisos en orden específico para Android 12+
  final perms = <Permission>[
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
    Permission.bluetooth,
    Permission.locationWhenInUse,
    Permission.location, // Agregar ubicación general
  ];

  bool allGranted = true;

  for (final p in perms) {
    final st = await p.status;
    print('Estado del permiso ${p.toString()}: ${st.toString()}');

    if (!st.isGranted) {
      print('⚠️  Solicitando permiso: ${p.toString()}');
      final result = await p.request();
      print('Resultado del permiso ${p.toString()}: ${result.toString()}');

      if (result.isDenied) {
        print('❌ Permiso denegado: ${p.toString()}');
        allGranted = false;
      } else if (result.isPermanentlyDenied) {
        print('❌ Permiso permanentemente denegado: ${p.toString()}');
        allGranted = false;
        // Mostrar diálogo para ir a configuración
        print(
            'Por favor, vaya a Configuración > Aplicaciones > Permisos y habilite los permisos de Bluetooth');
      } else if (result.isGranted) {
        print('✓ Permiso concedido: ${p.toString()}');
      }
    } else {
      print('✓ Permiso ya concedido: ${p.toString()}');
    }
  }

  if (!allGranted) {
    print('⚠️  ALGUNOS PERMISOS NO FUERON CONCEDIDOS');
    print('La funcionalidad de Bluetooth puede estar limitada.');
  } else {
    print('✅ TODOS LOS PERMISOS DE BLUETOOTH CONCEDIDOS');
  }

  // Verificar estado de Bluetooth
  try {
    print('=== VERIFICANDO ESTADO DE BLUETOOTH ===');
    final bluetoothState = await Permission.bluetooth.serviceStatus;
    print('Estado del servicio Bluetooth: $bluetoothState');
  } catch (e) {
    print('Error verificando estado de Bluetooth: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensurePermissions();

  final BluetoothRepository sppRepo =
      BluetoothRepositorySpp(BluetoothAdapterSpp());
  final BluetoothRepository bleRepo = BluetoothRepositoryBle(BleAdapter(
      config: BleUartConfig.truTest())); // Configuración específica para S3

  runApp(MyApp(sppRepo: sppRepo, bleRepo: bleRepo));
}

class MyApp extends StatelessWidget {
  final BluetoothRepository sppRepo;
  final BluetoothRepository bleRepo;
  const MyApp({super.key, required this.sppRepo, required this.bleRepo});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF1463FF), brightness: Brightness.light);
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ScanCubit(sppRepo, bleRepo)),
        BlocProvider(
            create: (_) => ConnectionBloc(
                _BridgeRepository(sppRepo, bleRepo), CommandRegistry())),
      ],
      child: MaterialApp(
        title: 'Pruebas Flutter',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          textTheme: GoogleFonts.interTextTheme(),
        ),
        home: const HomePage(),
      ),
    );
  }
}

/// Decide SPP o BLE - Tru-Test S3 es BLE aunque tenga formato MAC
class _BridgeRepository implements BluetoothRepository {
  final BluetoothRepository spp;
  final BluetoothRepository ble;
  BluetoothRepository? _active;

  _BridgeRepository(this.spp, this.ble);

  BluetoothRepository _pick(String id) {
    // Tru-Test S3 es BLE aunque tenga formato MAC
    if (id.toUpperCase().contains('DE:FD:76:A4:D7:ED')) {
      print('🎯 Detectada S3 - usando BLE');
      return ble;
    }
    // Resto de dispositivos por formato
    return id.contains(':') ? spp : ble;
  }

  @override
  Future<List<BtDevice>> bondedDevices() => spp.bondedDevices();

  @override
  Future<void> connect(String id) async {
    _active = _pick(id);
    await _active!.connect(id);
  }

  @override
  Future<void> disconnect() async {
    await _active?.disconnect();
    _active = null;
  }

  @override
  Future<bool> isConnected() async => await _active?.isConnected() ?? false;

  @override
  Stream<String> rawStream() => (_active ?? spp).rawStream();

  @override
  Future<void> sendCommand(String command) async {
    final a = _active;
    if (a == null) {
      throw StateError('No conectado');
    }
    await a.sendCommand(command);
  }

  @override
  Future<List<BtDevice>> scanNearby(
      {Duration timeout = const Duration(seconds: 8)}) async {
    final s = await spp.scanNearby(timeout: timeout);
    final b = await ble.scanNearby(timeout: timeout);
    return [...s, ...b];
  }
}

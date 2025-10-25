import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pruebas_flutter/presentation/bloc/ble_bloc.dart';
import 'package:pruebas_flutter/presentation/pages/ble_page.dart';
import 'package:pruebas_flutter/core/permissions/permission_service.dart';
import 'package:pruebas_flutter/data/ble/ble_datasource.dart';
import 'package:pruebas_flutter/data/ble/ble_repository_impl.dart';
import 'package:pruebas_flutter/domain/usecases/scan_devices.dart';
import 'package:pruebas_flutter/domain/usecases/connect_device.dart';
import 'package:pruebas_flutter/domain/usecases/disconnect_device.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BleApp());
}

class BleApp extends StatelessWidget {
  const BleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final permissionService = PermissionService();
    final dataSource = BleDataSource();
    final repository = BleRepositoryImpl(dataSource: dataSource);

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => BleBloc(
            scanDevices: ScanDevices(repository),
            connectDevice: ConnectDevice(repository),
            disconnectDevice: DisconnectDevice(repository),
            permissionService: permissionService,
          )..add(BleEvent.checkPermissions()),
        ),
      ],
      child: MaterialApp(
        title: 'BLE Devices',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.light,
        ),
        home: const BlePage(),
      ),
    );
  }
}
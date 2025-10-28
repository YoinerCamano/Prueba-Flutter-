import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities.dart';
import '../blocs/scan/scan_cubit.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../widgets/device_tile.dart';

class BlePage extends StatefulWidget {
  const BlePage({super.key});

  @override
  State<BlePage> createState() => _BlePageState();
}

class _BlePageState extends State<BlePage> {
  @override
  void initState() {
    super.initState();
    // Lanzar un escaneo unificado al abrir la pantalla
    context.read<ScanCubit>().scanUnified();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos BLE'),
        actions: [
          IconButton(
            tooltip: 'Escanear',
            onPressed: () => context.read<ScanCubit>().scanUnified(),
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<conn.ConnectionBloc, conn.ConnectionState>(
          listener: (context, state) {
            if (state is conn.ConnectionError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
          },
          builder: (context, state) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Indicador de escaneo
                  BlocBuilder<ScanCubit, ScanState>(
                    builder: (context, s) => s.scanning
                        ? const LinearProgressIndicator()
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: BlocBuilder<ScanCubit, ScanState>(
                      builder: (context, scanState) {
                        if (scanState.found.isEmpty) {
                          return const _EmptyHint();
                        }
                        return ListView.separated(
                          itemCount: scanState.found.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final d = scanState.found[index];
                            return DeviceTile(
                              device: d,
                              onTap: () => _connect(d),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _connect(BtDevice d) {
    context.read<conn.ConnectionBloc>().add(conn.ConnectRequested(d));
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_searching, size: 48),
            const SizedBox(height: 12),
            Text(
              'No se encontraron dispositivos BLE.\nPulsa el botón de buscar para escanear de nuevo.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pruebas_flutter/presentation/bloc/ble_bloc.dart';
import 'package:pruebas_flutter/presentation/widgets/device_tile.dart';

class BlePage extends StatelessWidget {
  const BlePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos BLE'),
        actions: [
          BlocBuilder<BleBloc, BleState>(
            builder: (context, state) {
              final bloc = context.read<BleBloc>();
              if (state.scanning) {
                return IconButton(
                  tooltip: 'Detener escaneo',
                  onPressed: () => bloc.add(BleEvent.stopScan()),
                  icon: const Icon(Icons.stop_circle_outlined),
                );
              }
              return IconButton(
                tooltip: 'Iniciar escaneo',
                onPressed: () => bloc.add(BleEvent.startScan()),
                icon: const Icon(Icons.search),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<BleBloc, BleState>(
          listenWhen: (p, c) => p.error != c.error && c.error != null,
          listener: (context, state) {
            final msg = state.error!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
            );
          },
          builder: (context, state) {
            if (!state.permissionsOk) {
              return _PermissionsHint(onOpenSettings: () {
                context.read<BleBloc>().add(BleEvent.checkPermissions());
              });
            }

            return Column(
              children: [
                if (state.scanning) const LinearProgressIndicator(),
                Expanded(
                  child: state.devices.isEmpty
                      ? const _EmptyHint()
                      : ListView.separated(
                          itemCount: state.devices.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final d = state.devices[index];
                            final connected = state.connectedIds.contains(d.id);
                            final connecting = state.connectingId == d.id;
                            return DeviceTile(
                              device: d,
                              connected: connected,
                              connecting: connecting,
                              onConnect: () => context.read<BleBloc>().add(BleEvent.connect(d.id)),
                              onDisconnect: () => context.read<BleBloc>().add(BleEvent.disconnect(d.id)),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PermissionsHint extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _PermissionsHint({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Permisos requeridos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'La app necesita permisos de Bluetooth (y ubicación en algunos dispositivos) para escanear y conectarse.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.refresh),
              label: const Text('Volver a verificar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24.0),
        child: Text(
          'Pulsa el ícono de búsqueda para escanear dispositivos BLE cercanos.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
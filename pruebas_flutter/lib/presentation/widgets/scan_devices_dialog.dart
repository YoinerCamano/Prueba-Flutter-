import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities.dart';
import '../blocs/scan/scan_cubit.dart';
import 'device_tile.dart';

class ScanDevicesDialog extends StatefulWidget {
  final Function(BtDevice) onDeviceSelected;

  const ScanDevicesDialog({
    super.key,
    required this.onDeviceSelected,
  });

  @override
  State<ScanDevicesDialog> createState() => _ScanDevicesDialogState();
}

class _ScanDevicesDialogState extends State<ScanDevicesDialog> {
  @override
  void initState() {
    super.initState();
    // Iniciar escaneo automáticamente al abrir el modal
    context.read<ScanCubit>().scanUnified();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.bluetooth_searching, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Buscar Dispositivos',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _closeDialog(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar',
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Estado del escaneo
            BlocBuilder<ScanCubit, ScanState>(
              builder: (context, state) {
                if (state.scanning) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Escaneando dispositivos cercanos...',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Escaneo completado',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () =>
                              context.read<ScanCubit>().scanUnified(),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 16),

            // Lista de dispositivos encontrados
            Text(
              'Dispositivos Encontrados',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: BlocBuilder<ScanCubit, ScanState>(
                builder: (context, state) {
                  if (state.found.isEmpty && !state.scanning) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bluetooth_disabled,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No se encontraron dispositivos',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Asegúrate de que el dispositivo esté\nencendido y en modo de emparejamiento',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: state.found.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final device = state.found[index];
                      return DeviceTile(
                        device: device,
                        onTap: () => _selectDevice(device),
                      );
                    },
                  );
                },
              ),
            ),

            // Botones de acción
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _closeDialog(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                BlocBuilder<ScanCubit, ScanState>(
                  builder: (context, state) {
                    return Expanded(
                      child: FilledButton.icon(
                        onPressed: state.scanning
                            ? () => context.read<ScanCubit>().stopScanning()
                            : () => context.read<ScanCubit>().scanUnified(),
                        icon: Icon(
                          state.scanning ? Icons.stop : Icons.search,
                          size: 18,
                        ),
                        label: Text(state.scanning ? 'Detener' : 'Buscar'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _selectDevice(BtDevice device) {
    // Detener escaneo antes de conectar
    context.read<ScanCubit>().stopScanning();

    // Cerrar diálogo y pasar el dispositivo seleccionado
    Navigator.of(context).pop();
    widget.onDeviceSelected(device);
  }

  void _closeDialog() {
    // Detener escaneo al cerrar
    context.read<ScanCubit>().stopScanning();
    Navigator.of(context).pop();
  }
}

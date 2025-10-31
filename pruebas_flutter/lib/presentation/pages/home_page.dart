import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/bluetooth_debug.dart';
import '../../domain/entities.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../blocs/scan/scan_cubit.dart';
import '../widgets/device_tile.dart';
import '../widgets/weight_card.dart';
import '../widgets/scan_devices_dialog.dart';
import '../widgets/scale_status_icon.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    print('🏠 === INICIALIZANDO HOME PAGE ===');
    print('📱 Cargando dispositivos vinculados automáticamente...');
    context.read<ScanCubit>().loadBonded();

    // Verificar si ya hay una conexión activa al iniciar
    print('🔍 Verificando conexión automática...');
    context
        .read<conn.ConnectionBloc>()
        .add(conn.CheckAutoConnectionRequested());
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Básculas – Monitor'),
        actions: [
          // 🎯 Icono de estado de la báscula
          BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
            builder: (context, connectionState) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ScaleStatusIcon(
                  isConnected: connectionState is conn.Connected,
                  weight: connectionState is conn.Connected
                      ? connectionState.weight
                      : null,
                  batteryVoltage: connectionState is conn.Connected
                      ? connectionState.batteryVoltage
                      : null,
                  batteryPercent: connectionState is conn.Connected
                      ? connectionState.batteryPercent
                      : null,
                  onTap: () {
                    // Mostrar detalles rápidos o ir a pantalla de detalles
                    if (connectionState is conn.Connected) {
                      _showScaleDetails(context, connectionState);
                    }
                  },
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Buscar dispositivos',
            onPressed: () => _showScanDialog(),
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<conn.ConnectionBloc, conn.ConnectionState>(
          listener: (context, state) {
            if (state is conn.ConnectionError) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(state.message)));
            }

            // Detener escaneo cuando se conecta exitosamente
            if (state is conn.Connected) {
              context.read<ScanCubit>().stopScanning();
              print('🛑 Escaneo detenido - dispositivo conectado');
            }
          },
          builder: (context, connState) {
            final connected = connState is conn.Connected;
            final connecting = connState is conn.Connecting;

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // === Tarjeta de lectura de peso, estado de conexión o mensaje vacío ===
                  if (connected)
                    WeightCard(
                      weight: connState.weight,
                      batteryVoltage: connState.batteryVoltage,
                      batteryPercent: connState.batteryPercent,
                    )
                  else if (connecting)
                    Card(
                      color: color.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              'Conectando...',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Estableciendo conexión con ${connState.device.name}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Card(
                      color: color.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No hay dispositivo conectado. Selecciona uno para iniciar.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // === Lista de dispositivos vinculados/emparejados únicamente ===
                  if (!connected && !connecting) ...[
                    Row(
                      children: [
                        Text(
                          'Dispositivos Emparejados',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        // Botón principal de actualizar
                        TextButton.icon(
                          onPressed: () =>
                              context.read<ScanCubit>().loadBonded(),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Actualizar'),
                        ),
                        // Menú desplegable para acciones adicionales
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'manual':
                                _checkManualConnection();
                                break;
                              case 'diagnostic':
                                _runDiagnostic();
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'manual',
                              child: Row(
                                children: [
                                  Icon(Icons.bluetooth_connected, size: 16),
                                  SizedBox(width: 8),
                                  Text('Verificar Manual'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'diagnostic',
                              child: Row(
                                children: [
                                  Icon(Icons.bug_report, size: 16),
                                  SizedBox(width: 8),
                                  Text('Diagnóstico'),
                                ],
                              ),
                            ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(Icons.more_vert),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: BlocBuilder<ScanCubit, ScanState>(
                        builder: (context, scanState) {
                          print(
                              '🎨 === UI REBUILD DISPOSITIVOS EMPAREJADOS ===');
                          print(
                              '📊 Dispositivos vinculados: ${scanState.bonded.length}');

                          final items = <Widget>[];

                          // Mostrar SOLO dispositivos vinculados/emparejados
                          for (final d in scanState.bonded) {
                            print(
                                '🎨 Agregando emparejado: ${d.name} (${d.id})');
                            items.add(
                              DeviceTile(
                                device: d,
                                onTap: () => _connect(d),
                              ),
                            );
                            items.add(const Divider(height: 1));
                          }

                          if (items.isEmpty) {
                            print('⚠️ UI: Lista vacía, mostrando mensaje');
                            items.add(
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.bluetooth_disabled,
                                        size: 48,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No hay dispositivos emparejados',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Usa el botón de búsqueda para encontrar nuevos dispositivos',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline,
                                            ),
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton.icon(
                                        onPressed: () => _showScanDialog(),
                                        icon:
                                            const Icon(Icons.search, size: 18),
                                        label:
                                            const Text('Buscar Dispositivos'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          } else {
                            print(
                                '✅ UI: Mostrando ${items.length ~/ 2} dispositivos emparejados');
                          }

                          return ListView(children: items);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // === Botón de control ===
                  FilledButton.tonalIcon(
                    onPressed: (connected || connecting)
                        ? () => context
                            .read<conn.ConnectionBloc>()
                            .add(conn.DisconnectRequested())
                        : null,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: Text(connecting ? 'Cancelar' : 'Desconectar'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _runDiagnostic() async {
    print('🔍 === EJECUTANDO DIAGNÓSTICO DESDE UI ===');

    // Mostrar indicador de progreso
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            '🔍 Ejecutando diagnóstico Bluetooth... Revisa la consola para detalles.'),
        duration: Duration(seconds: 3),
      ),
    );

    // Ejecutar diagnóstico en background
    await BluetoothDebug.runFullDiagnostic();

    // Mostrar resultado
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '✅ Diagnóstico completado. Revisa la consola para los resultados.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _connect(BtDevice d) {
    print('🔗 === INICIANDO CONEXIÓN DESDE UI ===');
    print('🎯 Dispositivo seleccionado: ${d.name} (${d.id})');
    context.read<conn.ConnectionBloc>().add(conn.ConnectRequested(d));
  }

  void _checkManualConnection() {
    // Buscar la S3 específica en los dispositivos emparejados
    final scanState = context.read<ScanCubit>().state;

    // Buscar la S3 por dirección MAC conocida
    final s3Device = scanState.bonded
        .where((device) =>
            device.id == 'DE:FD:76:A4:D7:ED' ||
            device.name.contains('S3') ||
            device.name.contains('680066'))
        .firstOrNull;

    if (s3Device != null) {
      print('🔍 Verificando conexión manual para S3: ${s3Device.name}');
      context
          .read<conn.ConnectionBloc>()
          .add(conn.CheckManualConnectionRequested(s3Device));

      // Mostrar mensaje informativo
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔍 Verificando si hay una conexión manual activa...'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // Si no encontramos la S3, mostrar mensaje y ofrecer actualizar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '⚠️ S3 no encontrada en dispositivos emparejados. Actualiza la lista.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// 📊 Mostrar detalles rápidos de la báscula
  void _showScaleDetails(BuildContext context, conn.Connected state) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.scale, color: Colors.green),
            const SizedBox(width: 8),
            Text('${state.device.name}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 📊 Información del peso
            if (state.weight != null) ...[
              _buildDetailRow(
                icon: Icons.monitor_weight,
                label: 'Peso',
                value: '${state.weight!.kg?.toStringAsFixed(1) ?? 'N/A'} kg',
                status: state.weight!.status,
              ),
              const SizedBox(height: 8),
            ],

            // 🔋 Información de batería
            if (state.batteryPercent != null) ...[
              _buildDetailRow(
                icon: Icons.battery_full,
                label: 'Batería',
                value:
                    '${state.batteryPercent!.percent?.toStringAsFixed(0) ?? 'N/A'}%',
              ),
              const SizedBox(height: 8),
            ],

            if (state.batteryVoltage != null) ...[
              _buildDetailRow(
                icon: Icons.electrical_services,
                label: 'Voltaje',
                value:
                    '${state.batteryVoltage!.volts?.toStringAsFixed(2) ?? 'N/A'} V',
              ),
              const SizedBox(height: 8),
            ],

            // 📱 Información de conexión
            _buildDetailRow(
              icon: Icons.bluetooth_connected,
              label: 'Estado',
              value: 'Conectado',
              status: WeightStatus.stable,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// 📋 Construir fila de detalle
  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    WeightStatus? status,
  }) {
    Color statusColor = Colors.green;
    if (status != null) {
      switch (status) {
        case WeightStatus.stable:
          statusColor = Colors.green;
          break;
        case WeightStatus.unstable:
          statusColor = Colors.orange;
          break;
        case WeightStatus.negative:
          statusColor = Colors.red;
          break;
      }
    }

    return Row(
      children: [
        Icon(icon, size: 20, color: statusColor),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: statusColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _showScanDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // No se puede cerrar tocando fuera
      builder: (context) => ScanDevicesDialog(
        onDeviceSelected: (device) => _connect(device),
      ),
    );
  }
}

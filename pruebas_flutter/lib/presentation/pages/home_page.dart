import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../blocs/scan/scan_cubit.dart';
import '../widgets/device_tile.dart';
import '../widgets/weight_card.dart';

enum TransportMode { spp, ble }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  TransportMode _mode = TransportMode.spp;

  @override
  void initState() {
    super.initState();
    print('🏠 === INICIALIZANDO HOME PAGE ===');
    print('📱 Cargando dispositivos vinculados automáticamente...');
    context.read<ScanCubit>().loadBonded();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Básculas – Monitor'),
        actions: [
          SegmentedButton<TransportMode>(
            segments: const [
              ButtonSegment(value: TransportMode.spp, label: Text('Clásico')),
              ButtonSegment(value: TransportMode.ble, label: Text('BLE')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          IconButton(
            tooltip: 'Escanear',
            onPressed: () => context.read<ScanCubit>().scan(mode: _mode),
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
          },
          builder: (context, connState) {
            final connected = connState is conn.Connected;

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // === Tarjeta de lectura de peso o mensaje vacío ===
                  if (connected)
                    WeightCard(
                      weight: connState.weight,
                      battery: connState.battery,
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

                  // === Lista de vinculados (solo en modo Clásico) ===
                  if (_mode == TransportMode.spp) ...[
                    Row(
                      children: [
                        Text(
                          'Vinculados (Clásico)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _checkManualConnection(),
                          icon: const Icon(Icons.bluetooth_connected, size: 16),
                          label: const Text('Verificar Manual'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () =>
                              context.read<ScanCubit>().loadBonded(),
                          child: const Text('Actualizar'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: BlocBuilder<ScanCubit, ScanState>(
                        builder: (context, scanState) {
                          print(
                              '🎨 === UI REBUILD DISPOSITIVOS VINCULADOS ===');
                          print(
                              '📊 Dispositivos en estado: ${scanState.bonded.length}');
                          print('🔄 Loading: ${scanState.loading}');
                          print('❌ Error: ${scanState.error}');

                          final items = <Widget>[];
                          for (final d in scanState.bonded) {
                            print('🎨 Agregando a UI: ${d.name} (${d.id})');
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
                              const ListTile(
                                title: Text(
                                  'No hay dispositivos emparejados. '
                                  'Empareja la S3 en Ajustes del sistema.',
                                ),
                              ),
                            );
                          } else {
                            print(
                                '✅ UI: Mostrando ${items.length ~/ 2} dispositivos');
                          }

                          return ListView(children: items);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // === Lista de dispositivos cercanos ===
                  Row(
                    children: [
                      Text(
                        'Cercanos (${_mode == TransportMode.spp ? 'Clásico' : 'BLE'})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      BlocBuilder<ScanCubit, ScanState>(
                        builder: (_, s) => s.scanning
                            ? const Text('Escaneando...')
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 170,
                    child: BlocBuilder<ScanCubit, ScanState>(
                      builder: (context, scanState) {
                        final items = <Widget>[];
                        for (final d in scanState.found) {
                          items.add(
                            DeviceTile(
                              device: d,
                              onTap: () => _connect(d),
                            ),
                          );
                          items.add(const Divider(height: 1));
                        }
                        return ListView(children: items);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // === Botones de control ===
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: connected
                            ? () => context
                                .read<conn.ConnectionBloc>()
                                .add(conn.DisconnectRequested())
                            : null,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Desconectar'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: connected
                            ? () => context
                                .read<conn.ConnectionBloc>()
                                .add(conn.SendCommandRequested('{RW}'))
                            : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Forzar lectura'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: connected
                            ? () => context
                                .read<conn.ConnectionBloc>()
                                .add(conn.SendCommandRequested('{BV}'))
                            : null,
                        icon: const Icon(Icons.battery_charging_full),
                        label: const Text('Leer BV'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: connected
                            ? () => context
                                .read<conn.ConnectionBloc>()
                                .add(conn.SendCommandRequested('{BC}'))
                            : null,
                        icon: const Icon(Icons.battery_std),
                        label: const Text('Leer BC'),
                      ),
                    ],
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
}

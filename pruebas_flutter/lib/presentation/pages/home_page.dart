import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/bluetooth_debug.dart';
import '../../domain/entities.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../blocs/scan/scan_cubit.dart';
import '../widgets/device_tile.dart';
import '../widgets/weight_card.dart';

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
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Básculas – Monitor'),
        actions: [
          IconButton(
            tooltip: 'Buscar dispositivos',
            onPressed: () => context.read<ScanCubit>().scanUnified(),
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

                  // === Botones de comando manual (solo si está conectado) ===
                  if (connected) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Comandos de Prueba',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _sendCommand('{RW}'),
                                  icon: const Icon(Icons.scale, size: 16),
                                  label: const Text('Peso'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => _sendCommand('{BV}'),
                                  icon: const Icon(Icons.battery_std, size: 16),
                                  label: const Text('Batería'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => _sendCommand('{BC}'),
                                  icon: const Icon(Icons.battery_charging_full,
                                      size: 16),
                                  label: const Text('Carga'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // === Lista de dispositivos disponibles ===
                  Row(
                    children: [
                      Text(
                        'Dispositivos Disponibles',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _checkManualConnection(),
                        icon: const Icon(Icons.bluetooth_connected, size: 16),
                        label: const Text('Verificar Manual'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _runDiagnostic(),
                        icon: const Icon(Icons.bug_report, size: 16),
                        label: const Text('Diagnóstico'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => context.read<ScanCubit>().loadBonded(),
                        child: const Text('Actualizar'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: BlocBuilder<ScanCubit, ScanState>(
                      builder: (context, scanState) {
                        print('🎨 === UI REBUILD DISPOSITIVOS ===');
                        print(
                            '📊 Dispositivos vinculados: ${scanState.bonded.length}');
                        print(
                            '📊 Dispositivos encontrados: ${scanState.found.length}');
                        print('🔄 Loading: ${scanState.loading}');
                        print('❌ Error: ${scanState.error}');

                        final items = <Widget>[];
                        final deviceIds = <String>{};

                        // Mostrar tanto dispositivos vinculados como encontrados
                        // Primero dispositivos vinculados
                        for (final d in scanState.bonded) {
                          if (!deviceIds.contains(d.id)) {
                            print(
                                '🎨 Agregando vinculado: ${d.name} (${d.id})');
                            items.add(
                              DeviceTile(
                                device: d,
                                onTap: () => _connect(d),
                              ),
                            );
                            items.add(const Divider(height: 1));
                            deviceIds.add(d.id);
                          }
                        }

                        // Luego dispositivos encontrados
                        for (final d in scanState.found) {
                          if (!deviceIds.contains(d.id)) {
                            print(
                                '🎨 Agregando encontrado: ${d.name} (${d.id})');
                            items.add(
                              DeviceTile(
                                device: d,
                                onTap: () => _connect(d),
                              ),
                            );
                            items.add(const Divider(height: 1));
                            deviceIds.add(d.id);
                          }
                        }

                        if (items.isEmpty) {
                          print('⚠️ UI: Lista vacía, mostrando mensaje');
                          items.add(
                            ListTile(
                              title: Text(
                                'No hay dispositivos disponibles. Usa el botón de búsqueda para encontrar básculas.',
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

                  // === Lista de dispositivos cercanos ===
                  Row(
                    children: [
                      Text(
                        'Dispositivos Cercanos',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      BlocBuilder<ScanCubit, ScanState>(
                        builder: (_, s) => s.scanning
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('Escaneando dispositivos...'),
                                ],
                              )
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

  void _sendCommand(String command) {
    print('📤 Enviando comando manual: $command');
    context.read<conn.ConnectionBloc>().add(conn.SendCommandRequested(command));
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

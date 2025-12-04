import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities.dart';
import '../../core/firebase_provider.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../blocs/scan/scan_cubit.dart';
import '../widgets/device_tile.dart';
import '../widgets/weight_card.dart';
import '../widgets/scan_devices_dialog.dart';
import '../widgets/firebase_widgets.dart';
import 'device_info_page.dart';
import 'configuration_page.dart';
import 'weighing_history_page.dart';
import 'bunch_table_page.dart';
// import '../widgets/device_info_loader.dart'; // Reemplazado por DeviceInfoPage
// import '../widgets/device_info_card.dart'; // Reemplazado por DeviceInfoLoader
// import '../widgets/scale_status_icon.dart'; // DESACTIVADO
// import '../widgets/device_info_widget.dart'; // Reemplazado por DeviceInfoCard

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Controla si el diálogo de "Conectando" está abierto
  bool _connectingDialogOpen = false;
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

    return BlocListener<conn.ConnectionBloc, conn.ConnectionState>(
      listener: (context, state) {
        // Mostrar dialog de conexión cuando está conectando
        if (state is conn.Connecting) {
          // Evitar abrir múltiples veces
          if (!_connectingDialogOpen) {
            _connectingDialogOpen = true;
          }
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => _buildConnectingDialog(state),
          );
        } else {
          // Cerrar el diálogo sólo si lo abrimos desde esta pantalla
          if (_connectingDialogOpen) {
            _connectingDialogOpen = false;
            // Usar rootNavigator para asegurarnos de cerrar el diálogo modal
            Navigator.of(context, rootNavigator: true).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Básculas – Monitor'),
          actions: [
            // 🎯 Icono de estado de la báscula - DESACTIVADO
            /* BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
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
          ), */
            // Ícono de historial de pesajes
            IconButton(
              tooltip: 'Historial de Pesajes',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WeighingHistoryPage(),
                  ),
                );
              },
              icon: const Icon(Icons.history),
            ),
            // Tabla diaria de racimos
            IconButton(
              tooltip: 'Tabla de Racimos',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BunchTablePage(),
                  ),
                );
              },
              icon: const Icon(Icons.table_chart),
            ),
            BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
              builder: (context, connectionState) {
                if (connectionState is conn.Connected) {
                  return IconButton(
                    tooltip: 'Acerca del dispositivo',
                    onPressed: () => _showDeviceInfo(context, connectionState),
                    icon: const Icon(Icons.info_outline),
                  );
                }
                return const SizedBox
                    .shrink(); // No mostrar si no está conectado
              },
            ),
            // ⚙️ Icono de configuración
            BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
              builder: (context, connectionState) {
                if (connectionState is conn.Connected) {
                  return IconButton(
                    tooltip: 'Configuración',
                    onPressed: () =>
                        _showConfiguration(context, connectionState),
                    icon: const Icon(Icons.settings),
                  );
                }
                return const SizedBox
                    .shrink(); // No mostrar si no está conectado
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
                    // === Tarjeta de lectura de peso o mensaje vacío ===
                    // El estado "connecting" ahora se muestra como un Dialog modal centrado
                    if (connected)
                      WeightCard(
                        weight: connState.weight,
                        batteryVoltage: connState.batteryVoltage,
                        batteryPercent: connState.batteryPercent,
                      )
                    else if (!connecting)
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
                    // === Botones de acción horizontal: GUARDAR PESAJE ===
                    if (connected)
                      BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
                        builder: (context, connState) {
                          final isStable = connState is conn.Connected &&
                              connState.weight?.status == WeightStatus.stable;

                          return Row(
                            children: [
                              // 💾 Botón GUARDAR PESAJE
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: isStable
                                      ? () => _saveWeighing(context, connState)
                                      : null,
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        isStable ? Colors.blue : Colors.grey,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                  ),
                                  icon: const Icon(Icons.save, size: 20),
                                  label: Text(
                                    isStable ? 'GUARDAR' : 'Esperando...',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                    const SizedBox(height: 16),

                    // === Últimos 5 pesajes ===
                    if (connected)
                      BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
                        buildWhen: (previous, current) {
                          // Solo reconstruir cuando cambie el dispositivo conectado
                          // No reconstruir en cada actualización de peso
                          if (previous is conn.Connected &&
                              current is conn.Connected) {
                            return previous.device.id != current.device.id;
                          }
                          return previous.runtimeType != current.runtimeType;
                        },
                        builder: (context, connState) {
                          if (connState is! conn.Connected) {
                            return const SizedBox.shrink();
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.history, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Últimos pesajes',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const WeighingHistoryPage(),
                                          ),
                                        );
                                      },
                                      child: const Text('Ver todos'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 280,
                                child: MeasurementHistoryWidget(
                                  sessionId: null,
                                  deviceId: connState.device.id,
                                  limit: 5,
                                ),
                              ),
                            ],
                          );
                        },
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
                                          icon: const Icon(Icons.search,
                                              size: 18),
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
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 🔄 Widget para mostrar el dialog de conexión centrado
  Widget _buildConnectingDialog(conn.Connecting state) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icono animado de Bluetooth
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bluetooth_searching,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),

            // Indicador de progreso
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Título
            Text(
              'Conectando',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 12),

            // Nombre del dispositivo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.scale,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      state.device.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Mensaje descriptivo
            Text(
              'Estableciendo conexión Bluetooth...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Por favor espera un momento',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.7),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _runDiagnostic() async {
    print('🔍 === DIAGNÓSTICO BLUETOOTH ===');
    // Funcionalidad de diagnóstico deshabilitada temporalmente
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ Diagnóstico no disponible en esta versión'),
        duration: Duration(seconds: 2),
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

  /// 📊 Mostrar detalles rápidos de la báscula - DESACTIVADO
  /* void _showScaleDetails(BuildContext context, conn.Connected state) {
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
  } */

  /// 💾 Guardar pesaje en Firebase
  Future<void> _saveWeighing(BuildContext context, conn.Connected state) async {
    final firebaseService = FirebaseProvider.of(context);
    final weight = state.weight;

    if (weight?.kg == null) return;

    // Obtener la unidad actual de la báscula (por defecto 'kg')
    final unit = state.weightUnit ?? 'kg';

    try {
      await firebaseService.saveMeasurement(
        deviceId: state.device.id,
        weight: weight!.kg!,
        unit: unit,
        sessionId: null,
        metadata: {},
      );

      // 🔄 Auto-guardar como entrada de racimo en la tabla diaria
      try {
        final tableId = await firebaseService.getOrCreateTodayBunchTable(
          deviceId: state.device.id,
        );
        final nextNumber = await firebaseService.getNextBunchNumber(tableId);
        await firebaseService.addBunchEntry(
          tableId: tableId,
          number: nextNumber,
          weightKg: weight.kg!,
          weighingTime: DateTime.now(),
        );
      } catch (e) {
        print('⚠️ Error auto-guardando racimo: $e');
      }

      // Obtener total de pesajes guardados
      final total = await firebaseService.getTotalMeasurements(
        deviceId: state.device.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '✅ Pesaje guardado - Total: $total registros',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Ver historial',
              textColor: Colors.white,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WeighingHistoryPage(),
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ Error guardando pesaje: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 📋 Navegar a la página de información del dispositivo
  void _showDeviceInfo(BuildContext context, conn.Connected state) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const DeviceInfoPage(),
      ),
    );
  }

  /// ⚙️ Navegar a la página de configuración
  void _showConfiguration(BuildContext context, conn.Connected state) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ConfigurationPage(),
      ),
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

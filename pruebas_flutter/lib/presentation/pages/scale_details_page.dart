import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/connection/connection_bloc.dart' as conn;
import '../widgets/scale_data_summary.dart';

/// 📊 Página dedicada para mostrar información detallada de la báscula
class ScaleDetailsPage extends StatelessWidget {
  const ScaleDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalles de la Báscula'),
        elevation: 0,
        actions: [
          BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
            builder: (context, state) {
              if (state is conn.Connected) {
                return IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Actualizar datos',
                  onPressed: () {
                    // Forzar nueva lectura
                    context.read<conn.ConnectionBloc>().add(
                          conn.SendCommandRequested('{RW}'),
                        );
                    context.read<conn.ConnectionBloc>().add(
                          conn.SendCommandRequested('{BV}'),
                        );
                    context.read<conn.ConnectionBloc>().add(
                          conn.SendCommandRequested('{BC}'),
                        );
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
        builder: (context, state) {
          return SingleChildScrollView(
            child: Column(
              children: [
                // 📊 Resumen principal de datos
                ScaleDataSummary(
                  isConnected: state is conn.Connected,
                  weight: state is conn.Connected ? state.weight : null,
                  batteryVoltage:
                      state is conn.Connected ? state.batteryVoltage : null,
                  batteryPercent:
                      state is conn.Connected ? state.batteryPercent : null,
                  device: state is conn.Connected ? state.device : null,
                ),

                if (state is conn.Connected) ...[
                  // 📈 Gráficos y estadísticas adicionales
                  _buildStatisticsCard(context, state),

                  // ⚙️ Controles de la báscula
                  _buildControlsCard(context, state),

                  // 🔧 Información técnica
                  _buildTechnicalInfoCard(context, state),
                ],

                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 📈 Tarjeta de estadísticas
  Widget _buildStatisticsCard(BuildContext context, conn.Connected state) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Estadísticas',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Placeholder para estadísticas futuras
            Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: colorScheme.surfaceVariant.withOpacity(0.3),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bar_chart,
                      size: 32,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Gráficos de tendencia',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Próximamente',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ⚙️ Tarjeta de controles
  Widget _buildControlsCard(BuildContext context, conn.Connected state) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Controles',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Botones de control
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    context.read<conn.ConnectionBloc>().add(
                          conn.SendCommandRequested('{Zero}'),
                        );
                  },
                  icon: const Icon(Icons.exposure_zero),
                  label: const Text('Zero'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    context.read<conn.ConnectionBloc>().add(
                          conn.SendCommandRequested('{RW}'),
                        );
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Leer Peso'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    context.read<conn.ConnectionBloc>().add(
                          conn.SendCommandRequested('{BV}'),
                        );
                  },
                  icon: const Icon(Icons.battery_std),
                  label: const Text('Voltaje'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    context.read<conn.ConnectionBloc>().add(
                          conn.SendCommandRequested('{BC}'),
                        );
                  },
                  icon: const Icon(Icons.battery_charging_full),
                  label: const Text('Porcentaje'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 🔧 Tarjeta de información técnica
  Widget _buildTechnicalInfoCard(BuildContext context, conn.Connected state) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Información Técnica',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Modelo', 'Tru-Test S3'),
            _buildInfoRow('MAC', state.device.id),
            _buildInfoRow('Protocolo', 'Bluetooth LE'),
            _buildInfoRow('Características', 'Lectura, Batería, Zero'),
            if (state.weight != null) ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              _buildInfoRow(
                'Última lectura',
                _formatDateTime(state.weight!.at),
              ),
            ],
            if (state.batteryVoltage != null) ...[
              _buildInfoRow(
                'Última lectura batería',
                _formatDateTime(state.batteryVoltage!.at),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 📋 Fila de información
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  /// 🕒 Formatear fecha y hora
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/'
        '${dateTime.month.toString().padLeft(2, '0')}/'
        '${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}:'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }
}

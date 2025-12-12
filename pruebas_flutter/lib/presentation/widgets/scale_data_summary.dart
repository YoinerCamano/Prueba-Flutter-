import 'package:flutter/material.dart';
import '../../domain/entities.dart';

/// 🎯 Widget expandido que muestra información detallada de la báscula
/// Incluye gráficos, tendencias y datos completos en una vista compacta
class ScaleDataSummary extends StatelessWidget {
  final bool isConnected;
  final WeightReading? weight;
  final BatteryStatus? batteryVoltage;
  final BatteryStatus? batteryPercent;
  final BtDevice? device;

  const ScaleDataSummary({
    super.key,
    required this.isConnected,
    this.weight,
    this.batteryVoltage,
    this.batteryPercent,
    this.device,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🏆 Header con estado principal
            _buildHeader(colorScheme),
            const SizedBox(height: 16),

            if (isConnected) ...[
              // 📊 Sección de peso
              _buildWeightSection(colorScheme),
              const SizedBox(height: 16),

              // 🔋 Sección de batería
              _buildBatterySection(colorScheme),
              const SizedBox(height: 16),

              // 📱 Información del dispositivo
              _buildDeviceSection(colorScheme),
            ] else ...[
              // Estado desconectado
              _buildDisconnectedState(colorScheme),
            ],
          ],
        ),
      ),
    );
  }

  /// 🏆 Header principal
  Widget _buildHeader(ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(
          isConnected ? Icons.scale : Icons.scale_outlined,
          size: 32,
          color: isConnected ? Colors.green : colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device?.name ?? 'Báscula',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                isConnected ? 'Conectado' : 'Desconectado',
                style: TextStyle(
                  fontSize: 14,
                  color: isConnected ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // Estado visual rápido
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected ? Colors.green : Colors.red,
          ),
        ),
      ],
    );
  }

  /// ⚖️ Sección de peso
  Widget _buildWeightSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.primaryContainer.withOpacity(0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.monitor_weight,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Peso',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (weight != null && weight!.kg != null) ...[
            Row(
              children: [
                Text(
                  '${weight!.kg!.toStringAsFixed(1)} kg',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _getWeightColor(),
                  ),
                ),
                const SizedBox(width: 12),
                _buildWeightStatusChip(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Última lectura: ${_formatTime(weight!.at)}',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            Text(
              'Sin datos',
              style: TextStyle(
                fontSize: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 🔋 Sección de batería
  Widget _buildBatterySection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.secondaryContainer.withOpacity(0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.battery_full,
                size: 20,
                color: colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Batería',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Porcentaje
              if (batteryPercent != null &&
                  batteryPercent!.percent != null) ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${batteryPercent!.percent!.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _getBatteryPercentColor(),
                        ),
                      ),
                      const Text(
                        'Porcentaje',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],

              // Voltaje
              if (batteryVoltage != null && batteryVoltage!.volts != null) ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${batteryVoltage!.volts!.toStringAsFixed(2)} V',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _getBatteryVoltageColor(),
                        ),
                      ),
                      const Text(
                        'Voltaje',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (batteryPercent == null && batteryVoltage == null) ...[
            Text(
              'Sin datos de batería',
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 📱 Sección del dispositivo
  Widget _buildDeviceSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surfaceVariant.withOpacity(0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bluetooth_connected,
                size: 20,
                color: colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Dispositivo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (device != null) ...[
            Text(
              device!.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'MAC: ${device!.id}',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 📱 Estado desconectado
  Widget _buildDisconnectedState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        children: [
          Icon(
            Icons.bluetooth_disabled,
            size: 64,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No conectado',
            style: TextStyle(
              fontSize: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Conecta una báscula para ver los datos',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 🏷️ Chip de estado del peso
  Widget _buildWeightStatusChip() {
    if (weight == null) return const SizedBox.shrink();

    String text;
    Color color;
    IconData icon;

    switch (weight!.status) {
      case WeightStatus.stable:
        text = 'Estable';
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case WeightStatus.unstable:
        text = 'Inestable';
        color = Colors.orange;
        icon = Icons.pending;
        break;
      case WeightStatus.negative:
        text = 'Negativo';
        color = Colors.red;
        icon = Icons.remove_circle;
        break;
      case WeightStatus.overload:
        text = 'Sobrecarga';
        color = Colors.deepOrange;
        icon = Icons.warning;
        break;
    }

    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        text,
        style: TextStyle(fontSize: 12, color: color),
      ),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color.withOpacity(0.3)),
    );
  }

  /// 🎨 Color del peso según estado
  Color _getWeightColor() {
    if (weight == null) return Colors.grey;

    switch (weight!.status) {
      case WeightStatus.stable:
        return Colors.green;
      case WeightStatus.unstable:
        return Colors.orange;
      case WeightStatus.negative:
        return Colors.red;
      case WeightStatus.overload:
        return Colors.deepOrange;
    }
  }

  /// 🎨 Color de batería por porcentaje
  Color _getBatteryPercentColor() {
    if (batteryPercent?.percent == null) return Colors.grey;

    final percent = batteryPercent!.percent!;
    if (percent > 60) return Colors.green;
    if (percent > 30) return Colors.orange;
    return Colors.red;
  }

  /// 🎨 Color de batería por voltaje
  Color _getBatteryVoltageColor() {
    if (batteryVoltage?.volts == null) return Colors.grey;

    final volts = batteryVoltage!.volts!;
    if (volts >= 3.8) return Colors.green;
    if (volts >= 3.6) return Colors.orange;
    return Colors.red;
  }

  /// 🕒 Formatear tiempo
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) {
      return 'Hace ${diff.inSeconds}s';
    } else if (diff.inMinutes < 60) {
      return 'Hace ${diff.inMinutes}m';
    } else {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}

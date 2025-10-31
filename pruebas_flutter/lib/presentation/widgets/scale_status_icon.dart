import 'package:flutter/material.dart';
import '../../domain/entities.dart';

/// 🎯 Widget de icono que muestra el estado de la báscula de forma compacta
/// Incluye indicadores visuales para conexión, peso, batería y estado general
class ScaleStatusIcon extends StatelessWidget {
  final bool isConnected;
  final WeightReading? weight;
  final BatteryStatus? batteryVoltage;
  final BatteryStatus? batteryPercent;
  final VoidCallback? onTap;

  const ScaleStatusIcon({
    super.key,
    required this.isConnected,
    this.weight,
    this.batteryVoltage,
    this.batteryPercent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getBorderColor(colorScheme),
            width: 2,
          ),
          color: _getBackgroundColor(colorScheme),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🏆 Icono principal de la báscula
            Icon(
              _getMainIcon(),
              size: 32,
              color: _getMainIconColor(colorScheme),
            ),
            const SizedBox(height: 4),

            // 📊 Indicadores de estado
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Estado de conexión
                _buildConnectionIndicator(colorScheme),
                const SizedBox(width: 6),

                // Estado de peso
                if (weight != null) ...[
                  _buildWeightIndicator(colorScheme),
                  const SizedBox(width: 6),
                ],

                // Estado de batería
                _buildBatteryIndicator(colorScheme),
              ],
            ),

            // 📱 Texto de estado compacto
            const SizedBox(height: 2),
            Text(
              _getStatusText(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _getTextColor(colorScheme),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// 🎯 Icono principal según el estado
  IconData _getMainIcon() {
    if (!isConnected) return Icons.scale_outlined;
    if (weight != null) {
      switch (weight!.status) {
        case WeightStatus.stable:
          return Icons.scale;
        case WeightStatus.unstable:
          return Icons.balance;
        case WeightStatus.negative:
          return Icons.remove_circle_outline;
      }
    }
    return Icons.scale;
  }

  /// 🎨 Color del icono principal
  Color _getMainIconColor(ColorScheme colorScheme) {
    if (!isConnected) return colorScheme.onSurfaceVariant;
    if (weight != null) {
      switch (weight!.status) {
        case WeightStatus.stable:
          return Colors.green;
        case WeightStatus.unstable:
          return Colors.orange;
        case WeightStatus.negative:
          return Colors.red;
      }
    }
    return colorScheme.primary;
  }

  /// 🔗 Indicador de conexión
  Widget _buildConnectionIndicator(ColorScheme colorScheme) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isConnected ? Colors.green : Colors.red,
      ),
    );
  }

  /// ⚖️ Indicador de peso
  Widget _buildWeightIndicator(ColorScheme colorScheme) {
    if (weight == null) return const SizedBox.shrink();

    Color weightColor;
    switch (weight!.status) {
      case WeightStatus.stable:
        weightColor = Colors.green;
        break;
      case WeightStatus.unstable:
        weightColor = Colors.orange;
        break;
      case WeightStatus.negative:
        weightColor = Colors.red;
        break;
    }

    return Icon(
      _getWeightStatusIcon(),
      size: 12,
      color: weightColor,
    );
  }

  /// 🔋 Indicador de batería
  Widget _buildBatteryIndicator(ColorScheme colorScheme) {
    IconData batteryIcon;
    Color batteryColor;

    // Priorizar porcentaje si está disponible, sino usar voltaje
    if (batteryPercent != null) {
      final percent = batteryPercent!.percent!;
      if (percent > 60) {
        batteryIcon = Icons.battery_full;
        batteryColor = Colors.green;
      } else if (percent > 30) {
        batteryIcon = Icons.battery_3_bar;
        batteryColor = Colors.orange;
      } else if (percent > 15) {
        batteryIcon = Icons.battery_2_bar;
        batteryColor = Colors.orange;
      } else {
        batteryIcon = Icons.battery_1_bar;
        batteryColor = Colors.red;
      }
    } else if (batteryVoltage != null) {
      final volts = batteryVoltage!.volts!;
      if (volts >= 3.8) {
        batteryIcon = Icons.battery_full;
        batteryColor = Colors.green;
      } else if (volts >= 3.6) {
        batteryIcon = Icons.battery_3_bar;
        batteryColor = Colors.orange;
      } else if (volts >= 3.4) {
        batteryIcon = Icons.battery_2_bar;
        batteryColor = Colors.orange;
      } else {
        batteryIcon = Icons.battery_1_bar;
        batteryColor = Colors.red;
      }
    } else {
      batteryIcon = Icons.battery_unknown;
      batteryColor = colorScheme.onSurfaceVariant;
    }

    return Icon(
      batteryIcon,
      size: 12,
      color: batteryColor,
    );
  }

  /// ⚖️ Icono específico del estado del peso
  IconData _getWeightStatusIcon() {
    if (weight == null) return Icons.help_outline;

    switch (weight!.status) {
      case WeightStatus.stable:
        return Icons.check_circle;
      case WeightStatus.unstable:
        return Icons.pending;
      case WeightStatus.negative:
        return Icons.remove_circle;
    }
  }

  /// 🎨 Color del borde
  Color _getBorderColor(ColorScheme colorScheme) {
    if (!isConnected) return colorScheme.outline;
    if (weight != null) {
      switch (weight!.status) {
        case WeightStatus.stable:
          return Colors.green.withOpacity(0.5);
        case WeightStatus.unstable:
          return Colors.orange.withOpacity(0.5);
        case WeightStatus.negative:
          return Colors.red.withOpacity(0.5);
      }
    }
    return colorScheme.primary.withOpacity(0.5);
  }

  /// 🎨 Color de fondo
  Color _getBackgroundColor(ColorScheme colorScheme) {
    if (!isConnected) return colorScheme.surfaceVariant.withOpacity(0.3);
    return colorScheme.primaryContainer.withOpacity(0.1);
  }

  /// 🎨 Color del texto
  Color _getTextColor(ColorScheme colorScheme) {
    if (!isConnected) return colorScheme.onSurfaceVariant;
    return colorScheme.onSurface;
  }

  /// 📱 Texto de estado
  String _getStatusText() {
    if (!isConnected) return 'Desconectado';

    if (weight != null && weight!.kg != null) {
      final weightText = '${weight!.kg!.toStringAsFixed(1)} kg';
      switch (weight!.status) {
        case WeightStatus.stable:
          return weightText;
        case WeightStatus.unstable:
          return '~$weightText';
        case WeightStatus.negative:
          return weightText;
      }
    }

    return 'Conectado';
  }
}

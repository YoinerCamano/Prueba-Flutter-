import 'package:flutter/material.dart';
import '../../domain/entities.dart';

class WeightCard extends StatelessWidget {
  final WeightReading? weight;
  final BatteryStatus? batteryVoltage;
  final BatteryStatus? batteryPercent;
  const WeightCard(
      {super.key, this.weight, this.batteryVoltage, this.batteryPercent});

  @override
  Widget build(BuildContext context) {
    final w = weight?.kg;
    final bVolt = batteryVoltage?.volts;
    final bPct = batteryPercent?.percent;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header con título y batería
            Row(
              children: [
                Text('Lectura de peso',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                // Iconos de batería separados
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icono de voltaje
                    if (bVolt != null) ...[
                      Icon(Icons.flash_on, color: Colors.blue, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        '${bVolt.toStringAsFixed(2)}V',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    // Icono de porcentaje
                    if (bPct != null) ...[
                      _buildBatteryIcon(bPct),
                      const SizedBox(width: 4),
                      Text(
                        '${bPct.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                    // Mensaje cuando no hay datos de batería
                    if (bVolt == null && bPct == null)
                      Text(
                        'Sin datos de batería',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Peso principal centrado (SOLO PESO)
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  w != null ? '${w.toStringAsFixed(2)} kg' : '--.-- kg',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Timestamp centrado
            if (weight?.at != null)
              Center(
                child: Text(
                  'Última lectura: ${TimeOfDay.fromDateTime(weight!.at).format(context)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryIcon(double? batteryPercent) {
    IconData icon;
    Color? color;

    if (batteryPercent == null) {
      icon = Icons.battery_unknown;
      color = Colors.grey;
    } else if (batteryPercent >= 90) {
      icon = Icons.battery_full;
      color = Colors.green;
    } else if (batteryPercent >= 60) {
      icon = Icons.battery_5_bar;
      color = Colors.green;
    } else if (batteryPercent >= 40) {
      icon = Icons.battery_4_bar;
      color = Colors.orange;
    } else if (batteryPercent >= 20) {
      icon = Icons.battery_2_bar;
      color = Colors.orange;
    } else {
      icon = Icons.battery_1_bar;
      color = Colors.red;
    }

    return Icon(icon, color: color, size: 20);
  }
}

import 'package:flutter/material.dart';
import '../../domain/entities.dart';

class WeightCard extends StatelessWidget {
  final WeightReading? weight;
  final BatteryStatus? battery;
  const WeightCard({super.key, this.weight, this.battery});

  @override
  Widget build(BuildContext context) {
    final w = weight?.kg;
    final bVolt = battery?.volts;
    final bPct = battery?.percent;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lectura de peso', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                w != null ? '${w.toStringAsFixed(2)} kg' : '--.-- kg',
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.battery_full),
                const SizedBox(width: 8),
                Text(
                  bPct != null
                      ? '${bPct.toStringAsFixed(0)} %'
                      : bVolt != null
                          ? '${bVolt.toStringAsFixed(2)} V'
                          : 'Batería: N/D',
                ),
                const Spacer(),
                Text(
                  weight?.at != null ? TimeOfDay.fromDateTime(weight!.at).format(context) : '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

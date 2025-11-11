import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities.dart';
import '../blocs/connection/connection_bloc.dart' as conn;

class WeightCard extends StatefulWidget {
  final WeightReading? weight;
  final BatteryStatus? batteryVoltage;
  final BatteryStatus? batteryPercent;

  const WeightCard({
    super.key,
    this.weight,
    this.batteryVoltage,
    this.batteryPercent,
  });

  @override
  State<WeightCard> createState() => _WeightCardState();
}

class _WeightCardState extends State<WeightCard> {
  late final conn.ConnectionBloc _connectionBloc;

  @override
  void initState() {
    super.initState();
    // Guardar referencia al bloc antes de usarlo
    _connectionBloc = context.read<conn.ConnectionBloc>();
    // 🚀 Iniciar polling cuando se muestra la tarjeta de peso
    print('🚀 WeightCard montado - Iniciando polling de peso...');
    _connectionBloc.add(conn.StartPolling());
  }

  @override
  void dispose() {
    // 🛑 Detener polling cuando se oculta la tarjeta
    print('🛑 WeightCard desmontado - Deteniendo polling de peso...');
    _connectionBloc.add(conn.StopPolling());
    super.dispose();
  }

  Color _getWeightColor(WeightStatus status) {
    switch (status) {
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

  String _getStatusText(WeightStatus status) {
    switch (status) {
      case WeightStatus.stable:
        return 'Estable';
      case WeightStatus.unstable:
        return 'Inestable';
      case WeightStatus.negative:
        return 'Negativo';
      case WeightStatus.overload:
        return 'Sobrecarga';
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.weight?.kg;
    final bVolt = widget.batteryVoltage?.volts;
    final bPct = widget.batteryPercent?.percent;

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
            // Peso principal centrado con color según estado
            Center(
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      w != null
                          ? '${w.toStringAsFixed(2)} kg'
                          : (widget.weight?.status == WeightStatus.overload
                              ? '--- kg'
                              : '--.-- kg'),
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: widget.weight != null
                                ? _getWeightColor(widget.weight!.status)
                                : null,
                          ),
                    ),
                  ),
                  // Indicador de estado del peso
                  if (widget.weight != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getWeightColor(widget.weight!.status)
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getWeightColor(widget.weight!.status)
                              .withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _getStatusText(widget.weight!.status),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _getWeightColor(widget.weight!.status),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Timestamp centrado
            if (widget.weight?.at != null)
              Center(
                child: Text(
                  'Última lectura: ${TimeOfDay.fromDateTime(widget.weight!.at).format(context)}',
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

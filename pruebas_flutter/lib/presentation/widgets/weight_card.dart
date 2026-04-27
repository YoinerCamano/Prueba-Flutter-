import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities.dart';
import '../blocs/connection/connection_bloc.dart' as conn;

class WeightCard extends StatefulWidget {
  const WeightCard({super.key});

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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
      buildWhen: (prev, curr) {
        if (prev is conn.Connected && curr is conn.Connected) {
          return prev.weight?.kg != curr.weight?.kg ||
              prev.weight?.status != curr.weight?.status ||
              prev.weightUnit != curr.weightUnit;
        }
        return prev.runtimeType != curr.runtimeType;
      },
      builder: (context, state) {
        final connState = state is conn.Connected ? state : null;
        final w = connState?.weight?.kg;
        final weight = connState?.weight;
        final String unit =
            (connState?.weightUnit?.isNotEmpty == true) ? connState!.weightUnit! : 'kg';

        return Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainer,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header con título
                Row(
                  children: [
                    const Icon(Icons.monitor_weight, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Peso Actual',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Peso principal centrado con color según estado
                Center(
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          w != null
                              ? '${w.toStringAsFixed(2)} $unit'
                              : (weight?.status == WeightStatus.overload
                                  ? '--- $unit'
                                  : '--.-- $unit'),
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: weight != null
                                    ? _getWeightColor(weight.status)
                                    : null,
                              ),
                        ),
                      ),

                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }
}

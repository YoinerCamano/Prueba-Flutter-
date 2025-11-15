import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../blocs/persistence/measurement_persistence_cubit.dart';
import '../../domain/entities.dart';
import '../../core/firebase_provider.dart';
import '../widgets/firebase_widgets.dart';

/// Página de ejemplo que muestra cómo integrar Firebase con el pesaje
class WeighingWithFirebasePage extends StatefulWidget {
  const WeighingWithFirebasePage({super.key});

  @override
  State<WeighingWithFirebasePage> createState() =>
      _WeighingWithFirebasePageState();
}

class _WeighingWithFirebasePageState extends State<WeighingWithFirebasePage> {
  @override
  Widget build(BuildContext context) {
    // Proveer el cubit localmente usando los servicios del contexto
    final firebaseService = FirebaseProvider.of(context);
    final connectionBloc = context.read<conn.ConnectionBloc>();

    return BlocProvider<MeasurementPersistenceCubit>(
      create: (_) =>
          MeasurementPersistenceCubit(firebaseService, connectionBloc),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Registro de Pesaje'),
          actions: [
            BlocBuilder<MeasurementPersistenceCubit,
                MeasurementPersistenceState>(
              builder: (context, state) {
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Chip(
                    label: Text('${state.savedMeasurementsCount} guardados'),
                    backgroundColor: Colors.blue,
                    labelStyle: const TextStyle(color: Colors.white),
                  ),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // Botón de guardar pesaje
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
                      builder: (context, connState) {
                        final isStable = connState is conn.Connected &&
                            connState.weight?.status == WeightStatus.stable;

                        return ElevatedButton.icon(
                          onPressed: isStable
                              ? () async {
                                  final cubit = context
                                      .read<MeasurementPersistenceCubit>();
                                  final saved = await cubit.saveNow();

                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(saved
                                            ? '✅ Pesaje guardado'
                                            : '⚠️ Peso no estable'),
                                        backgroundColor: saved
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                    );
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.save, size: 24),
                          label: Text(
                            isStable
                                ? 'GUARDAR PESAJE'
                                : 'Esperando peso estable...',
                            style: const TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                isStable ? Colors.blue : Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(18),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Peso actual
            Expanded(
              child: BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
                builder: (context, state) {
                  if (state is! conn.Connected) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bluetooth_disabled,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No conectado a ningún dispositivo'),
                        ],
                      ),
                    );
                  }

                  final weight = state.weight;
                  if (weight == null || weight.kg == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${weight.kg!.toStringAsFixed(1)} kg',
                          style: const TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildStatusChip(weight.status),
                        const SizedBox(height: 8),
                        BlocBuilder<MeasurementPersistenceCubit,
                            MeasurementPersistenceState>(
                          builder: (context, pState) {
                            final n = pState.savedMeasurementsCount;
                            return Chip(
                              avatar: const Icon(Icons.confirmation_number,
                                  color: Colors.white, size: 18),
                              label: Text('Pesaje #$n'),
                              backgroundColor: Colors.blue,
                              labelStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        if (state.batteryPercent?.percent != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.battery_full,
                                  color: Colors.green),
                              const SizedBox(width: 8),
                              Text(
                                '${state.batteryPercent!.percent!.toStringAsFixed(0)}%',
                                style: const TextStyle(fontSize: 18),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Botón para ver historial
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Últimos pesajes',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 240,
                    child: Builder(
                      builder: (context) {
                        final connState =
                            context.read<conn.ConnectionBloc>().state;
                        String? deviceId;
                        if (connState is conn.Connected) {
                          deviceId = connState.device.id;
                        }
                        return MeasurementHistoryWidget(
                          sessionId: null,
                          deviceId: deviceId,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(WeightStatus status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case WeightStatus.stable:
        color = Colors.green;
        label = 'ESTABLE';
        icon = Icons.check_circle;
        break;
      case WeightStatus.unstable:
        color = Colors.orange;
        label = 'INESTABLE';
        icon = Icons.warning;
        break;
      case WeightStatus.overload:
        color = Colors.red;
        label = 'SOBRECARGA';
        icon = Icons.error;
        break;
      case WeightStatus.negative:
        color = Colors.grey;
        label = 'NEGATIVO';
        icon = Icons.remove_circle;
        break;
    }

    return Chip(
      avatar: Icon(icon, color: Colors.white, size: 18),
      label: Text(label),
      backgroundColor: color,
      labelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

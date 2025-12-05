import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/firebase_provider.dart';

/// Widget que muestra el historial de mediciones desde Firebase
class MeasurementHistoryWidget extends StatelessWidget {
  final String? sessionId;
  final String? deviceId;
  final DateTime? startDate;
  final DateTime? endDate;
  final int limit;
  final bool selectionMode;
  final Set<String> selectedIds;
  final Function(String id, bool selected)? onSelectionChanged;
  final Function(List<String> allIds)? onSelectAll;

  const MeasurementHistoryWidget({
    super.key,
    this.sessionId,
    this.deviceId,
    this.startDate,
    this.endDate,
    this.limit = 50,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.onSelectionChanged,
    this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final firebaseService = FirebaseProvider.of(context);

    // Usar getAllBunchEntries en lugar de getMeasurements
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: firebaseService?.getAllBunchEntries(limit: limit),
      builder: (context, snapshot) {
        // Mostrar loading solo si no hay datos previos
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
              ],
            ),
          );
        }

        final measurements = snapshot.data ?? [];

        if (measurements.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text('No hay pesajes registrados'),
              ],
            ),
          );
        }

        // Notificar los IDs disponibles para la función "seleccionar todos"
        if (selectionMode && onSelectAll != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final allIds = measurements.map((m) => m['id'] as String).toList();
            onSelectAll!(allIds);
          });
        }

        return ListView.builder(
          itemCount: measurements.length,
          itemBuilder: (context, index) {
            final measurement = measurements[index];
            final measurementId = measurement['id'] as String;
            final weight =
                measurement['weight'] ?? measurement['weightKg'] ?? 0.0;
            final unit = measurement['unit'] ?? 'kg';
            final timestamp = measurement['timestamp'] ??
                measurement['weighingTime'] ??
                measurement['createdAt'];
            final isSelected = selectedIds.contains(measurementId);

            // Datos adicionales del racimo
            final number = measurement['number'] ?? index + 1;
            final cintaColor = measurement['cintaColor'] ?? '';
            final cuadrilla = measurement['cuadrilla'] ?? '';
            final lote = measurement['lote'] ?? '';
            final recusado = measurement['recusado'] ?? false;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: isSelected ? Colors.blue.shade50 : null,
              child: ListTile(
                leading: selectionMode
                    ? Checkbox(
                        value: isSelected,
                        onChanged: (selected) {
                          onSelectionChanged?.call(
                              measurementId, selected ?? false);
                        },
                      )
                    : CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Text(
                          '#$number',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                title: Row(
                  children: [
                    Text(
                      '$weight $unit',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (recusado)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Recusado',
                          style: TextStyle(fontSize: 10, color: Colors.red),
                        ),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      _formatTimestamp(timestamp),
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (cintaColor.isNotEmpty ||
                        cuadrilla.isNotEmpty ||
                        lote.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if (cintaColor.isNotEmpty) 'Cinta: $cintaColor',
                            if (cuadrilla.isNotEmpty) 'Cuadrilla: $cuadrilla',
                            if (lote.isNotEmpty) 'Lote: $lote',
                          ].join(' | '),
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ),
                  ],
                ),
                trailing: selectionMode
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Eliminar pesaje'),
                              content: const Text('¿Eliminar este registro?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancelar'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Eliminar',
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true && context.mounted) {
                            try {
                              await firebaseService
                                  ?.deleteMeasurement(measurementId);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Pesaje eliminado')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            }
                          }
                        },
                      ),
                onTap: selectionMode
                    ? () {
                        onSelectionChanged?.call(measurementId, !isSelected);
                      }
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Sin fecha';
    try {
      DateTime? dt;
      if (timestamp is Timestamp) {
        dt = timestamp.toDate();
      } else if (timestamp is DateTime) {
        dt = timestamp;
      } else if (timestamp is String) {
        dt = DateTime.tryParse(timestamp);
      }
      if (dt == null) return 'Sin fecha';
      final dd = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      final yyyy = dt.year.toString();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      final ss = dt.second.toString().padLeft(2, '0');
      return '$dd/$mo/$yyyy $hh:$mm:$ss';
    } catch (e) {
      return 'Sin fecha';
    }
  }
}

/// Widget que muestra las sesiones activas
class SessionsWidget extends StatelessWidget {
  final String? deviceId;

  const SessionsWidget({super.key, this.deviceId});

  @override
  Widget build(BuildContext context) {
    final firebaseService = FirebaseProvider.of(context);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: firebaseService?.getSessions(deviceId: deviceId, limit: 20),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final sessions = snapshot.data ?? [];

        if (sessions.isEmpty) {
          return const Center(
            child: Text('No hay sesiones registradas'),
          );
        }

        return ListView.builder(
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            final session = sessions[index];
            final status = session['status'] ?? 'unknown';
            final count = session['measurementCount'] ?? 0;
            final startTime = session['startTime'];

            return Card(
              child: ListTile(
                leading: Icon(
                  status == 'active' ? Icons.play_circle : Icons.check_circle,
                  color: status == 'active' ? Colors.green : Colors.grey,
                  size: 32,
                ),
                title: Text('Sesión ${session['id']}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$count mediciones'),
                    if (startTime != null)
                      Text('Inicio: ${_formatTimestamp(startTime)}'),
                  ],
                ),
                trailing: status == 'active'
                    ? const Chip(
                        label: Text('ACTIVA'),
                        backgroundColor: Colors.green,
                        labelStyle: TextStyle(color: Colors.white),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Sin fecha';
    try {
      DateTime? dt;
      if (timestamp is Timestamp) {
        dt = timestamp.toDate();
      } else if (timestamp is DateTime) {
        dt = timestamp;
      } else if (timestamp is String) {
        dt = DateTime.tryParse(timestamp);
      }
      if (dt == null) return 'Sin fecha';
      final dd = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      final yyyy = dt.year.toString();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$dd/$mo/$yyyy $hh:$mm';
    } catch (e) {
      return 'Sin fecha';
    }
  }
}

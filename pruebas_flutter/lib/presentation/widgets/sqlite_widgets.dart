import 'package:flutter/material.dart';
import '../../core/database_provider.dart';
import 'bunch_colors.dart';

class BunchFilters {
  final DateTime? startDate;
  final DateTime? endDate;
  final double? minWeight;
  final double? maxWeight;
  final String? color;
  final String? cuadrilla;
  final String? lote;
  final int recusadoFilter; // 0 todos, 1 si, 2 no
  final int syncedFilter; // 0 todos, 1 si, 2 no

  const BunchFilters({
    this.startDate,
    this.endDate,
    this.minWeight,
    this.maxWeight,
    this.color,
    this.cuadrilla,
    this.lote,
    this.recusadoFilter = 0,
    this.syncedFilter = 0,
  });

  bool get isEmpty =>
      startDate == null &&
      endDate == null &&
      minWeight == null &&
      maxWeight == null &&
      (color == null || color!.trim().isEmpty) &&
      (cuadrilla == null || cuadrilla!.trim().isEmpty) &&
      (lote == null || lote!.trim().isEmpty) &&
      recusadoFilter == 0 &&
      syncedFilter == 0;
}

/// Widget que muestra el historial de racimos desde SQLite
class BunchHistoryWidget extends StatelessWidget {
  final int limit;
  final bool selectionMode;
  final Set<int> selectedIds;
  final BunchFilters filters;
  final Function(int id, bool selected)? onSelectionChanged;
  final Function(List<int> allIds)? onSelectAll;

  const BunchHistoryWidget({
    super.key,
    this.limit = 50,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.filters = const BunchFilters(),
    this.onSelectionChanged,
    this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final databaseService = DatabaseProvider.of(context);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: databaseService.streamBunchEntries(limit: limit),
      builder: (context, snapshot) {
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

        final bunches = snapshot.data ?? [];
        final filteredBunches = _applyFilters(bunches);

        if (selectionMode && onSelectAll != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final allIds =
                filteredBunches.map((b) => b['id'] as int? ?? 0).toList();
            onSelectAll!(allIds);
          });
        }

        if (filteredBunches.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text('No hay racimos registrados'),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: filteredBunches.length,
          itemBuilder: (context, index) {
            final bunch = filteredBunches[index];
            final bunchId = bunch['id'] as int;
            final number = bunch['number'] ?? 0;
            final weightKg = bunch['weightKg'] ?? 0.0;
            final weighingTime = bunch['weighingTime'] as String?;
            final cintaColor = bunch['cintaColor'] ?? '';
            final cuadrilla = bunch['cuadrilla'] ?? '';
            final operario = bunch['operario'] ?? '';
            final bascula = bunch['bascula'] ?? '';
            final basculaModelo = bunch['bascula_modelo'] ?? '';
            final lote = bunch['lote'] ?? '';
            final recusado = bunch['recusado'] == 1;
            final synced =
                (bunch['syncedToFirebase'] ?? bunch['synced'] ?? 0) == 1;
            final isSelected = selectedIds.contains(bunchId);

            // Formatear fecha
            DateTime? dateTime;
            try {
              if (weighingTime != null) {
                dateTime = DateTime.parse(weighingTime);
              }
            } catch (e) {
              // Si falla el parsing, usar fecha actual
              dateTime = DateTime.now();
            }

            final dateStr = dateTime != null
                ? '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}'
                : 'Sin fecha';
            final timeStr = dateTime != null
                ? '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}'
                : '';

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              elevation: isSelected ? 4 : 1,
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: ListTile(
                onTap: selectionMode
                    ? () => onSelectionChanged?.call(bunchId, !isSelected)
                    : null,
                onLongPress: !selectionMode
                    ? () => onSelectionChanged?.call(bunchId, true)
                    : null,
                leading: selectionMode
                    ? Checkbox(
                        value: isSelected,
                        onChanged: (selected) {
                          if (selected != null) {
                            onSelectionChanged?.call(bunchId, selected);
                          }
                        },
                      )
                    : CircleAvatar(
                        backgroundColor: recusado
                            ? Colors.red
                            : (cintaColor.isNotEmpty
                                ? _parseColor(cintaColor)
                                : Colors.green),
                        child: Text(
                          '#$number',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                title: Row(
                  children: [
                    Text(
                      '${weightKg.toStringAsFixed(2)} kg',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (recusado)
                      const Chip(
                        label: Text('RECUSADO', style: TextStyle(fontSize: 10)),
                        backgroundColor: Colors.red,
                        labelStyle: TextStyle(color: Colors.white),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    const Spacer(),
                    if (!synced)
                      const Icon(Icons.cloud_off, size: 16, color: Colors.grey),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$dateStr $timeStr'),
                    if (cuadrilla.isNotEmpty ||
                        operario.isNotEmpty ||
                        bascula.isNotEmpty)
                      Text(
                        [
                          if (cuadrilla.isNotEmpty) 'Cuadrilla: $cuadrilla',
                          if (operario.isNotEmpty) 'Operario: $operario',
                          if (bascula.isNotEmpty)
                            'Báscula: $bascula${basculaModelo.isNotEmpty ? " ($basculaModelo)" : ""}',
                          if (lote.isNotEmpty) 'Lote: $lote',
                        ].join(' • '),
                        style: const TextStyle(fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                trailing: selectionMode
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.delete_outline),
                        color: Colors.red,
                        onPressed: () => _deleteBunch(context, bunchId, number),
                      ),
              ),
            );
          },
        );
      },
    );
  }

  Color _parseColor(String colorStr) {
    // Mapear nombres o códigos de colores a Color
    final colorMap = {
      'rojo': Colors.red,
      'marrón': Colors.brown,
      'marron': Colors.brown,
      'azul': Colors.blue,
      'verde': Colors.green,
      'amarillo': Colors.yellow,
      'naranja': Colors.orange,
      'morado': Colors.purple,
      'rosa': Colors.pink,
      'negro': Colors.black,
      'blanco': Colors.white,
    };
    final lower = colorStr.toLowerCase();
    if (colorMap.containsKey(lower)) {
      return colorMap[lower]!;
    }
    // Probar con códigos numéricos de cinta
    return BunchColors.getColorWidget(colorStr);
  }

  Future<void> _deleteBunch(
      BuildContext context, int bunchId, int number) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar racimo'),
        content: Text('¿Eliminar racimo #$number?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        final databaseService = DatabaseProvider.of(context);
        await databaseService.deleteBunchEntry(id: bunchId);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Racimo eliminado correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> bunches) {
    if (filters.isEmpty) return bunches;
    final minW = filters.minWeight;
    final maxW = filters.maxWeight;
    final colorQuery = (filters.color ?? '').trim().toLowerCase();
    final cuadrillaQuery = (filters.cuadrilla ?? '').trim().toLowerCase();
    final loteQuery = (filters.lote ?? '').trim().toLowerCase();

    return bunches.where((b) {
      // Peso
      final rawWeight = b['weightKg'];
      final weight = rawWeight is num
          ? rawWeight.toDouble()
          : double.tryParse(rawWeight?.toString() ?? '') ?? 0;
      if (minW != null && weight < minW) return false;
      if (maxW != null && weight > maxW) return false;

      // Color
      if (colorQuery.isNotEmpty) {
        final cColor = (b['cintaColor'] ?? '').toString();
        final lowerColor = cColor.toLowerCase();
        final colorName = BunchColors.getColorName(cColor).toLowerCase();
        final matchesCode = lowerColor.contains(colorQuery);
        final matchesName = colorName.contains(colorQuery);
        if (!(matchesCode || matchesName)) return false;
      }

      // Cuadrilla
      if (cuadrillaQuery.isNotEmpty) {
        final current = (b['cuadrilla'] ?? '').toString().toLowerCase();
        if (!current.contains(cuadrillaQuery)) return false;
      }

      // Lote
      if (loteQuery.isNotEmpty) {
        final current = (b['lote'] ?? '').toString().toLowerCase();
        if (!current.contains(loteQuery)) return false;
      }

      // Recusado
      if (filters.recusadoFilter != 0) {
        final recusado = b['recusado'] == 1;
        if (filters.recusadoFilter == 1 && !recusado) return false;
        if (filters.recusadoFilter == 2 && recusado) return false;
      }

      // Sincronización
      if (filters.syncedFilter != 0) {
        final synced =
            (b['syncedToFirebase'] ?? b['synced'] ?? 0).toString() == '1';
        if (filters.syncedFilter == 1 && !synced) return false;
        if (filters.syncedFilter == 2 && synced) return false;
      }

      // Fechas
      if (filters.startDate != null || filters.endDate != null) {
        try {
          final raw = b['weighingTime'];
          DateTime? dt;
          if (raw is String) dt = DateTime.parse(raw).toLocal();
          if (dt != null) {
            if (filters.startDate != null && dt.isBefore(filters.startDate!))
              return false;
            if (filters.endDate != null && dt.isAfter(filters.endDate!)) {
              return false;
            }
          }
        } catch (_) {
          // Si no se puede parsear, no filtrar por fecha
        }
      }

      return true;
    }).toList();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/database_provider.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../widgets/sqlite_widgets.dart';
import 'bunch_table_page.dart';

/// Página para ver el historial de racimos
class WeighingHistoryPage extends StatefulWidget {
  const WeighingHistoryPage({super.key});

  @override
  State<WeighingHistoryPage> createState() => _WeighingHistoryPageState();
}

class _WeighingHistoryPageState extends State<WeighingHistoryPage> {
  int _limit = 50;
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};
  List<int> _allAvailableIds = [];
  BunchFilters _filters = const BunchFilters();

  // Filtros avanzados
  final TextEditingController _minWeightCtrl = TextEditingController();
  final TextEditingController _maxWeightCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController();
  final TextEditingController _cuadrillaCtrl = TextEditingController();
  final TextEditingController _loteCtrl = TextEditingController();
  int _recusadoFilter = 0; // 0 todos, 1 sí, 2 no
  int _syncedFilter = 0; // 0 todos, 1 sí, 2 no
  DateTime? _startDate;
  DateTime? _endDate;

  // 🎯 Referencia al BLoC para detener/reanudar polling
  late final conn.ConnectionBloc _connectionBloc;

  @override
  void initState() {
    super.initState();
    print('📊 WeighingHistoryPage - Iniciando...');

    // Guardar referencia al bloc
    _connectionBloc = context.read<conn.ConnectionBloc>();

    // 🛑 DETENER POLLING DE PESO
    print('🛑 Deteniendo polling de peso...');
    _connectionBloc.add(conn.StopPolling());
  }

  @override
  void dispose() {
    // 🔄 Reanudar polling al salir
    print('🔄 WeighingHistoryPage dispose - Reanudando polling...');
    _connectionBloc.add(conn.StartPolling());
    _minWeightCtrl.dispose();
    _maxWeightCtrl.dispose();
    _colorCtrl.dispose();
    _cuadrillaCtrl.dispose();
    _loteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        // 🔄 Al salir de la página, reanudar polling
        if (didPop) {
          print('🔄 PopScope - Reanudando polling...');
          _connectionBloc.add(conn.StartPolling());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selectionMode
              ? '${_selectedIds.length} seleccionados'
              : 'Historial de Racimos'),
          leading: _selectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _selectionMode = false;
                      _selectedIds.clear();
                    });
                  },
                )
              : null,
          actions: [
            if (_selectionMode) ...[
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: 'Seleccionar todos',
                onPressed: _allAvailableIds.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _selectedIds.addAll(_allAvailableIds);
                        });
                      },
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: 'Eliminar seleccionados',
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () => _deleteSelectedBunches(context),
              ),
            ] else ...[
              IconButton(
                icon: const Icon(Icons.table_chart),
                tooltip: 'Tabla de Racimos',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BunchTablePage(),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.checklist),
                tooltip: 'Selección múltiple',
                onPressed: () {
                  setState(() {
                    _selectionMode = true;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.filter_alt),
                tooltip: 'Filtros',
                onPressed: _openFiltersSheet,
              ),
            ],
          ],
        ),
        body: Column(
          children: [
            // Info de límite
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Mostrando últimos $_limit racimos',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const Spacer(),
                    if (!_filters.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Filtros activos',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Lista de racimos
            Expanded(
              child: BunchHistoryWidget(
                limit: _limit,
                selectionMode: _selectionMode,
                selectedIds: _selectedIds,
                filters: _filters,
                onSelectionChanged: (id, selected) {
                  setState(() {
                    if (selected) {
                      _selectedIds.add(id);
                    } else {
                      _selectedIds.remove(id);
                    }
                  });
                },
                onSelectAll: (allIds) {
                  setState(() {
                    _allAvailableIds = allIds;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSelectedBunches(BuildContext context) async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar racimos'),
        content: Text('¿Eliminar $count racimos seleccionados?'),
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

    if (confirm == true && mounted) {
      try {
        final databaseService = DatabaseProvider.of(context);

        // Eliminar todos los seleccionados
        for (final id in _selectedIds) {
          await databaseService.deleteBunchEntry(id: id);
        }

        setState(() {
          _selectedIds.clear();
          _selectionMode = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ $count racimos eliminados correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
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

  // ----- Filtros -----
  void _openFiltersSheet() {
    // Sincronizar controles con filtros actuales
    _minWeightCtrl.text = _filters.minWeight?.toString() ?? '';
    _maxWeightCtrl.text = _filters.maxWeight?.toString() ?? '';
    _colorCtrl.text = _filters.color ?? '';
    _cuadrillaCtrl.text = _filters.cuadrilla ?? '';
    _loteCtrl.text = _filters.lote ?? '';
    _recusadoFilter = _filters.recusadoFilter;
    _syncedFilter = _filters.syncedFilter;
    _startDate = _filters.startDate;
    _endDate = _filters.endDate;

    int tempLimit = _limit;
    DateTime? tempStart = _startDate;
    DateTime? tempEnd = _endDate;
    int tempRecusado = _recusadoFilter;
    int tempSynced = _syncedFilter;
    bool showAdvanced = !_filters.isEmpty &&
        (_filters.minWeight != null ||
            _filters.maxWeight != null ||
            (_filters.color ?? '').isNotEmpty ||
            (_filters.cuadrilla ?? '').isNotEmpty ||
            (_filters.lote ?? '').isNotEmpty ||
            _filters.recusadoFilter != 0 ||
            _filters.syncedFilter != 0);

    String _fmt(DateTime? dt) {
      if (dt == null) return 'Sin fecha';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    }

    DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
    DateTime _endOfDay(DateTime d) =>
        DateTime(d.year, d.month, d.day, 23, 59, 59);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> pickRange() async {
              final now = DateTime.now();
              final pickedStart = await showDatePicker(
                context: ctx,
                initialDate: tempStart ?? now,
                firstDate: DateTime(2020),
                lastDate: DateTime(now.year + 1),
              );
              if (pickedStart != null) {
                final pickedEnd = await showDatePicker(
                  context: ctx,
                  initialDate: pickedStart,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(now.year + 1),
                );
                setModalState(() {
                  tempStart = _startOfDay(pickedStart);
                  tempEnd =
                      pickedEnd != null ? _endOfDay(pickedEnd) : _endOfDay(pickedStart);
                });
              }
            }

            void applyAndClose() {
              setState(() {
                _limit = tempLimit;
                _recusadoFilter = tempRecusado;
                _syncedFilter = tempSynced;
                _startDate = tempStart;
                _endDate = tempEnd;
                _filters = BunchFilters(
                  startDate: tempStart,
                  endDate: tempEnd,
                  minWeight: _parseDouble(_minWeightCtrl.text),
                  maxWeight: _parseDouble(_maxWeightCtrl.text),
                  color: _colorCtrl.text.trim().isEmpty
                      ? null
                      : _colorCtrl.text.trim(),
                  cuadrilla: _cuadrillaCtrl.text.trim().isEmpty
                      ? null
                      : _cuadrillaCtrl.text.trim(),
                  lote: _loteCtrl.text.trim().isEmpty
                      ? null
                      : _loteCtrl.text.trim(),
                  recusadoFilter: tempRecusado,
                  syncedFilter: tempSynced,
                );
              });
              Navigator.pop(ctx);
            }

            void resetAll() {
              setModalState(() {
                tempStart = null;
                tempEnd = null;
                tempLimit = 50;
                tempRecusado = 0;
                tempSynced = 0;
                _minWeightCtrl.clear();
                _maxWeightCtrl.clear();
                _colorCtrl.clear();
                _cuadrillaCtrl.clear();
                _loteCtrl.clear();
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.filter_alt, size: 18),
                        const SizedBox(width: 8),
                        const Text('Filtros', style: TextStyle(fontSize: 16)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setModalState(
                              () => showAdvanced = !showAdvanced),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                showAdvanced
                                    ? Icons.expand_less
                                    : Icons.tune,
                              ),
                              const SizedBox(width: 4),
                              Text(showAdvanced
                                  ? 'Ocultar avanzados'
                                  : 'Filtros avanzados'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Fecha', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.today),
                          label: const Text('Hoy'),
                          onPressed: () {
                            final now = DateTime.now();
                            setModalState(() {
                              tempStart = _startOfDay(now);
                              tempEnd = _endOfDay(now);
                            });
                          },
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.calendar_view_week),
                          label: const Text('Ayer'),
                          onPressed: () {
                            final now = DateTime.now();
                            final yesterday = now.subtract(const Duration(days: 1));
                            setModalState(() {
                              tempStart = _startOfDay(yesterday);
                              tempEnd = _endOfDay(yesterday);
                            });
                          },
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.date_range),
                          label: const Text('Desde - hasta'),
                          onPressed: pickRange,
                        ),
                        OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              tempStart = null;
                              tempEnd = null;
                            });
                          },
                          child: const Text('Limpiar fechas'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Desde: ${_fmt(tempStart)}'),
                    Text('Hasta: ${_fmt(tempEnd)}'),
                    const Divider(height: 24),
                    const Text('Cantidad a mostrar'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [20, 50, 100, 200].map((value) {
                        final selected = tempLimit == value;
                        return ChoiceChip(
                          label: Text('Últimos $value'),
                          selected: selected,
                          onSelected: (_) =>
                              setModalState(() => tempLimit = value),
                        );
                      }).toList(),
                    ),
                    if (showAdvanced) ...[
                      const Divider(height: 32),
                      const Text('Filtros avanzados',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 150,
                            child: TextField(
                              controller: _minWeightCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Peso mínimo (kg)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: TextField(
                              controller: _maxWeightCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Peso máximo (kg)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: TextField(
                              controller: _colorCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Color de cinta',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: TextField(
                              controller: _cuadrillaCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Cuadrilla',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: TextField(
                              controller: _loteCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Lote',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Recusado'),
                              const SizedBox(height: 6),
                              ToggleButtons(
                                isSelected: [
                                  tempRecusado == 0,
                                  tempRecusado == 1,
                                  tempRecusado == 2,
                                ],
                                constraints:
                                    const BoxConstraints(minHeight: 36, minWidth: 64),
                                onPressed: (idx) =>
                                    setModalState(() => tempRecusado = idx),
                                children: const [
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Text('Todos'),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Text('Sí'),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Text('No'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Sincronizado'),
                              const SizedBox(height: 6),
                              ToggleButtons(
                                isSelected: [
                                  tempSynced == 0,
                                  tempSynced == 1,
                                  tempSynced == 2,
                                ],
                                constraints:
                                    const BoxConstraints(minHeight: 36, minWidth: 64),
                                onPressed: (idx) =>
                                    setModalState(() => tempSynced = idx),
                                children: const [
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Text('Todos'),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Text('Sí'),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Text('No'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: resetAll,
                          child: const Text('Limpiar todo'),
                        ),
                        ElevatedButton.icon(
                          onPressed: applyAndClose,
                          icon: const Icon(Icons.check),
                          label: const Text('Aplicar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  double? _parseDouble(String value) {
    final parsed = double.tryParse(value.trim());
    return parsed;
  }
}

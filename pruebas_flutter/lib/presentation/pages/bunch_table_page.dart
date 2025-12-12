import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/database_provider.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../widgets/bunch_colors.dart';

/// Formatea la fecha en formato: HH:MM DD/MM/AAAA
String formatWeighingTime(dynamic weighingTime) {
  if (weighingTime == null) return '';
  try {
    DateTime dateTime;
    if (weighingTime is String) {
      dateTime = DateTime.parse(weighingTime);
    } else if (weighingTime is DateTime) {
      dateTime = weighingTime;
    } else {
      return '';
    }
    return DateFormat('HH:mm dd/MM/yyyy').format(dateTime);
  } catch (_) {
    return '';
  }
}

class BunchTablePage extends StatefulWidget {
  final String tableId;
  const BunchTablePage({super.key, this.tableId = 'local'});

  @override
  State<BunchTablePage> createState() => _BunchTablePageState();
}

class _BunchTablePageState extends State<BunchTablePage> {
  late final conn.ConnectionBloc _connectionBloc;

  @override
  void initState() {
    super.initState();
    _connectionBloc = context.read<conn.ConnectionBloc>();
    _connectionBloc.add(conn.StopPolling());
  }

  @override
  void dispose() {
    _connectionBloc.add(conn.StartPolling());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          _connectionBloc.add(conn.StartPolling());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tabla de Racimos'),
        ),
        body: _BunchEntriesList(tableId: widget.tableId),
      ),
    );
  }
}

class _BunchEntriesList extends StatefulWidget {
  final String tableId;
  const _BunchEntriesList({required this.tableId});

  @override
  State<_BunchEntriesList> createState() => _BunchEntriesListState();
}

class _BunchEntriesListState extends State<_BunchEntriesList> {
  final _minWeightCtrl = TextEditingController();
  final _maxWeightCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _cuadrillaCtrl = TextEditingController();
  final _loteCtrl = TextEditingController();

  List<String> _lastColors = const [];
  List<String> _lastCuadrillas = const [];
  List<String> _lastLotes = const [];

  DateTime? _startDate;
  DateTime? _endDate;
  int _recusadoFilter = 0; // 0: todos, 1: solo recusados, 2: sin recusados
  int _syncedFilter = 0; // 0: todos, 1: solo sincronizados, 2: pendientes
  bool _showAdvancedFilters = false; // ocultar avanzados por defecto

  void _openFiltersSheet() {
    setState(() => _showAdvancedFilters = false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String _fmt(DateTime? dt) {
          if (dt == null) return '—';
          return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
            left: 12,
            right: 12,
            top: 12,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Filtros',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.calendar_view_week),
                      label: const Text('Ayer'),
                      onPressed: () {
                        _setYesterdayRange();
                        setState(() {});
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.today),
                      label: const Text('Hoy'),
                      onPressed: () {
                        _setTodayRange();
                        setState(() {});
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: const Text('Desde - hasta'),
                      onPressed: () async {
                        await _pickDate(isStart: true);
                        await _pickDate(isStart: false);
                        setState(() {});
                      },
                    ),
                    Text('Desde: ${_fmt(_startDate)}',
                        style: const TextStyle(fontSize: 12)),
                    Text('Hasta: ${_fmt(_endDate)}',
                        style: const TextStyle(fontSize: 12)),
                    IconButton(
                      tooltip: 'Reiniciar a ayer y hoy',
                      icon: const Icon(Icons.refresh),
                      onPressed: () {
                        _setDefaultDateRange();
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const Divider(height: 24),
                TextButton.icon(
                  onPressed: () => setState(
                      () => _showAdvancedFilters = !_showAdvancedFilters),
                  icon: Icon(
                    _showAdvancedFilters ? Icons.expand_less : Icons.tune,
                  ),
                  label: Text(_showAdvancedFilters
                      ? 'Ocultar filtros avanzados'
                      : 'Filtros avanzados'),
                ),
                if (_showAdvancedFilters)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: _AdvancedFiltersCard(
                      minWeightCtrl: _minWeightCtrl,
                      maxWeightCtrl: _maxWeightCtrl,
                      colorCtrl: _colorCtrl,
                      cuadrillaCtrl: _cuadrillaCtrl,
                      loteCtrl: _loteCtrl,
                      availableColors: _lastColors,
                      availableCuadrillas: _lastCuadrillas,
                      availableLotes: _lastLotes,
                      recusadoFilter: _recusadoFilter,
                      syncedFilter: _syncedFilter,
                      onFilterChanged: () => setState(() {}),
                      onRecusadoChange: (v) =>
                          setState(() => _recusadoFilter = v),
                      onSyncedChange: (v) => setState(() => _syncedFilter = v),
                      onReset: _resetFilters,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _setDefaultDateRange();
  }

  @override
  void dispose() {
    _minWeightCtrl.dispose();
    _maxWeightCtrl.dispose();
    _colorCtrl.dispose();
    _cuadrillaCtrl.dispose();
    _loteCtrl.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _minWeightCtrl.clear();
    _maxWeightCtrl.clear();
    _colorCtrl.clear();
    _cuadrillaCtrl.clear();
    _loteCtrl.clear();
    _setDefaultDateRange();
    _recusadoFilter = 0;
    _syncedFilter = 0;
    setState(() {});
  }

  void _setDefaultDateRange() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    _startDate = startOfToday.subtract(const Duration(days: 1));
    _endDate =
        startOfToday.add(const Duration(hours: 23, minutes: 59, seconds: 59));
  }

  void _setTodayRange() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    setState(() {
      _startDate = startOfToday;
      _endDate = startOfToday.add(
        const Duration(hours: 23, minutes: 59, seconds: 59),
      );
    });
  }

  void _setYesterdayRange() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
    setState(() {
      _startDate = startOfYesterday;
      _endDate = startOfToday.subtract(const Duration(seconds: 1));
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? (_startDate ?? now) : (_endDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate =
              picked.add(const Duration(hours: 23, minutes: 59, seconds: 59));
        }
      });
    }
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> docs) {
    final minW = double.tryParse(_minWeightCtrl.text.trim());
    final maxW = double.tryParse(_maxWeightCtrl.text.trim());
    final colorInput = _colorCtrl.text.trim().toLowerCase();
    String? colorCode = colorInput;
    String? colorName;
    if (colorInput.contains('-')) {
      final parts = colorInput.split('-');
      colorCode = parts.first.trim();
      colorName = parts.skip(1).join('-').trim();
    }
    if ((colorName == null || colorName.isEmpty) && colorCode.isNotEmpty) {
      colorName = BunchColors.getColorName(colorCode).toLowerCase();
    }

    final cuadrilla = _cuadrillaCtrl.text.trim().toLowerCase();
    final lote = _loteCtrl.text.trim().toLowerCase();

    return docs.where((d) {
      final rawWeight = d['weightKg'];
      final weight = rawWeight is num
          ? rawWeight.toDouble()
          : double.tryParse(rawWeight?.toString() ?? '') ?? 0;
      if (minW != null && weight < minW) return false;
      if (maxW != null && weight > maxW) return false;

      final cColor = (d['cintaColor'] ?? '').toString().toLowerCase();
      final cColorName =
          BunchColors.getColorName(d['cintaColor']?.toString()).toLowerCase();
      if (colorInput.isNotEmpty) {
        final matchesCode = colorCode != null &&
            colorCode.isNotEmpty &&
            cColor.contains(colorCode);
        final matchesName = colorName != null && colorName.isNotEmpty
            ? cColorName.contains(colorName)
            : false;
        if (!(matchesCode || matchesName)) return false;
      }

      final cCuadrilla = (d['cuadrilla'] ?? '').toString().toLowerCase();
      if (cuadrilla.isNotEmpty && !cCuadrilla.contains(cuadrilla)) {
        return false;
      }

      final cLote = (d['lote'] ?? '').toString().toLowerCase();
      if (lote.isNotEmpty && !cLote.contains(lote)) return false;

      if (_recusadoFilter != 0) {
        final recusado = d['recusado'] == 1;
        if (_recusadoFilter == 1 && !recusado) return false;
        if (_recusadoFilter == 2 && recusado) return false;
      }

      if (_syncedFilter != 0) {
        final synced = d['synced'] == 1;
        if (_syncedFilter == 1 && !synced) return false;
        if (_syncedFilter == 2 && synced) return false;
      }

      if (_startDate != null || _endDate != null) {
        try {
          final raw = d['weighingTime'];
          DateTime? dt;
          if (raw is String) dt = DateTime.parse(raw).toLocal();
          if (dt != null) {
            if (_startDate != null && dt.isBefore(_startDate!)) return false;
            if (_endDate != null && dt.isAfter(_endDate!)) return false;
          }
        } catch (_) {
          // Si no se puede parsear, no filtrar por fecha
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final databaseService = DatabaseProvider.of(context);

    print(
        '🔍 BunchTablePage: Construyendo lista con tableId: ${widget.tableId}');

    return StreamBuilder(
      stream: databaseService.streamBunchEntries(limit: 1000),
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
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
              ],
            ),
          );
        }

        final docs = snapshot.data ?? [];
        final filteredDocs = _applyFilters(docs);

        // Valores únicos para autocompletar filtros
        final colors = docs
            .map((d) => (d['cintaColor'] ?? '').toString().trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
        final cuadrillas = docs
            .map((d) => (d['cuadrilla'] ?? '').toString().trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
        final lotes = docs
            .map((d) => (d['lote'] ?? '').toString().trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));

        _lastColors = colors;
        _lastCuadrillas = cuadrillas;
        _lastLotes = lotes;

        Widget filtersButton = Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () => _openFiltersSheet(),
              icon: const Icon(Icons.filter_alt),
              label: const Text('Filtros'),
            ),
          ),
        );

        if (filteredDocs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                filtersButton,
                const SizedBox(height: 12),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.filter_alt_off,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('Sin resultados con los filtros actuales'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            filtersButton,
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: filteredDocs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final d = filteredDocs[index];
                  final entryId = d['id'].toString();
                  final number = d['number'] ?? index + 1;
                  final weightKg = (d['weightKg'] ?? 0).toDouble();
                  final weighingTime = d['weighingTime'];
                  final cintaColor = d['cintaColor'] as String?;
                  final cuadrilla = d['cuadrilla'] as String?;
                  final lote = d['lote'] as String?;
                  final recusado = (d['recusado'] == 1);
                  final recusadoDesc = d['recusadoDesc'] as String?;

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('#$number',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(width: 12),
                              Text('Peso: ${weightKg.toStringAsFixed(2)} kg'),
                              const Spacer(),
                              Text(
                                formatWeighingTime(weighingTime),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _EditableFieldsRow(
                            key: ValueKey(
                                entryId), // ✅ Key para preservar estado
                            entryId: entryId,
                            cintaColor: cintaColor,
                            cuadrilla: cuadrilla,
                            lote: lote,
                            recusado: recusado,
                            recusadoDesc: recusadoDesc,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AdvancedFiltersCard extends StatelessWidget {
  final TextEditingController minWeightCtrl;
  final TextEditingController maxWeightCtrl;
  final TextEditingController colorCtrl;
  final TextEditingController cuadrillaCtrl;
  final TextEditingController loteCtrl;
  final List<String> availableColors;
  final List<String> availableCuadrillas;
  final List<String> availableLotes;
  final int recusadoFilter;
  final int syncedFilter;
  final VoidCallback onFilterChanged;
  final ValueChanged<int> onRecusadoChange;
  final ValueChanged<int> onSyncedChange;
  final VoidCallback onReset;

  const _AdvancedFiltersCard({
    required this.minWeightCtrl,
    required this.maxWeightCtrl,
    required this.colorCtrl,
    required this.cuadrillaCtrl,
    required this.loteCtrl,
    required this.availableColors,
    required this.availableCuadrillas,
    required this.availableLotes,
    required this.recusadoFilter,
    required this.syncedFilter,
    required this.onFilterChanged,
    required this.onRecusadoChange,
    required this.onSyncedChange,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.filter_alt, size: 18),
                SizedBox(width: 8),
                Text('Filtros', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: minWeightCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Peso mínimo (kg)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => onFilterChanged(),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: maxWeightCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Peso máximo (kg)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => onFilterChanged(),
                  ),
                ),
                _AutocompleteField(
                  label: 'Color cinta',
                  controller: colorCtrl,
                  options: availableColors,
                  optionLabelBuilder: (value) {
                    if (value.isEmpty) return value;
                    final name = BunchColors.getColorName(value);
                    return name.toLowerCase() == value.toLowerCase()
                        ? value
                        : '$value - $name';
                  },
                  onChanged: onFilterChanged,
                ),
                _AutocompleteField(
                  label: 'Cuadrilla',
                  controller: cuadrillaCtrl,
                  options: availableCuadrillas,
                  onChanged: onFilterChanged,
                ),
                _AutocompleteField(
                  label: 'Lote',
                  controller: loteCtrl,
                  options: availableLotes,
                  onChanged: onFilterChanged,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Recusado', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    ToggleButtons(
                      isSelected: [
                        recusadoFilter == 0,
                        recusadoFilter == 1,
                        recusadoFilter == 2,
                      ],
                      constraints: const BoxConstraints(minHeight: 36),
                      onPressed: (idx) {
                        onRecusadoChange(idx);
                      },
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
                    const Text('Sincronizado', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    ToggleButtons(
                      isSelected: [
                        syncedFilter == 0,
                        syncedFilter == 1,
                        syncedFilter == 2,
                      ],
                      constraints: const BoxConstraints(minHeight: 36),
                      onPressed: (idx) {
                        onSyncedChange(idx);
                      },
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
                // Fecha se maneja en bloque principal de fechas
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.refresh),
                label: const Text('Limpiar filtros avanzados'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutocompleteField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final List<String> options;
  final VoidCallback onChanged;
  final String Function(String option)? optionLabelBuilder;

  const _AutocompleteField({
    required this.label,
    required this.controller,
    required this.options,
    required this.onChanged,
    this.optionLabelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final labelBuilder = optionLabelBuilder ?? (String option) => option;
    return SizedBox(
      width: 150,
      child: Autocomplete<String>(
        optionsBuilder: (TextEditingValue textEditingValue) {
          final query = textEditingValue.text.toLowerCase();
          return options.where((option) {
            final label = labelBuilder(option).toLowerCase();
            return label.contains(query);
          });
        },
        displayStringForOption: labelBuilder,
        initialValue: TextEditingValue(text: controller.text),
        onSelected: (String selection) {
          controller.text = labelBuilder(selection);
          onChanged();
        },
        optionsViewBuilder:
            (BuildContext context, void Function(String) onSelected, options) {
          final optionList = options.toList();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              child: SizedBox(
                width: 220,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: optionList.length,
                  itemBuilder: (context, index) {
                    final option = optionList[index];
                    final label = labelBuilder(option);
                    return ListTile(
                      dense: true,
                      title: Text(label),
                      onTap: () => onSelected(option),
                    );
                  },
                ),
              ),
            ),
          );
        },
        fieldViewBuilder: (
          BuildContext context,
          TextEditingController textEditingController,
          FocusNode focusNode,
          VoidCallback onFieldSubmitted,
        ) {
          textEditingController.text = controller.text;
          textEditingController.selection = TextSelection.collapsed(
            offset: textEditingController.text.length,
          );

          return TextField(
            controller: textEditingController,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) {
              controller.text = value;
              onChanged();
            },
            onEditingComplete: onFieldSubmitted,
          );
        },
      ),
    );
  }
}

class _EditableFieldsRow extends StatefulWidget {
  final String entryId;
  final String? cintaColor;
  final String? cuadrilla;
  final String? lote;
  final bool recusado;
  final String? recusadoDesc;

  const _EditableFieldsRow({
    super.key,
    required this.entryId,
    this.cintaColor,
    this.cuadrilla,
    this.lote,
    required this.recusado,
    this.recusadoDesc,
  });

  @override
  State<_EditableFieldsRow> createState() => _EditableFieldsRowState();
}

class _EditableFieldsRowState extends State<_EditableFieldsRow> {
  late TextEditingController _loteCtrl;
  late TextEditingController _recusadoDescCtrl;
  late bool _recusado;
  String? _selectedColor;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loteCtrl = TextEditingController(text: widget.lote ?? '');
    _recusadoDescCtrl = TextEditingController(text: widget.recusadoDesc ?? '');
    _recusado = widget.recusado;
    _selectedColor = widget.cintaColor;
  }

  @override
  void dispose() {
    _loteCtrl.dispose();
    _recusadoDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    print('🔍 DEBUG: _save() iniciado, _isEditing antes: $_isEditing');
    final databaseService = DatabaseProvider.of(context);

    // ✅ Cerrar edición INMEDIATAMENTE
    if (mounted) {
      print('🔍 DEBUG: Widget mounted, ejecutando setState');
      setState(() {
        print('🔍 DEBUG: Dentro de setState, cambiando _isEditing a false');
        _isEditing = false;
      });
      print('🔍 DEBUG: setState ejecutado, _isEditing ahora: $_isEditing');
    } else {
      print('❌ DEBUG: Widget NO mounted!');
    }

    // 🔄 Guardar en background
    try {
      await databaseService.updateBunchEntryFields(
        id: int.parse(widget.entryId), // SQLite usa INTEGER id
        cintaColor: _selectedColor?.trim().isEmpty ?? true
            ? null
            : _selectedColor?.trim(),
        cuadrilla: widget.cuadrilla, // NO EDITABLE - mantener original
        lote: _loteCtrl.text.trim().isEmpty ? null : _loteCtrl.text.trim(),
        recusado: _recusado,
        recusadoDesc: _recusado ? _recusadoDescCtrl.text : null,
      );

      // ✅ Mostrar confirmación DESPUÉS de guardar exitosamente
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('✅ Cambios guardados correctamente'),
              ],
            ),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
      print('✅ Racimo actualizado exitosamente');
    } catch (e) {
      print('❌ Error guardando: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('❌ Error al guardar: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _delete() async {
    final databaseService = DatabaseProvider.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar racimo'),
        content:
            const Text('¿Estás seguro de que deseas eliminar este racimo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      try {
        await databaseService.deleteBunchEntry(
          id: int.parse(widget.entryId), // SQLite usa INTEGER id
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Racimo eliminado')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🔍 DEBUG: _EditableFieldsRow.build() - _isEditing: $_isEditing');
    final colorName = BunchColors.getColorName(_selectedColor);

    if (!_isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DisplayRow(
              label: 'Color de cinta',
              value: colorName.isEmpty ? '(Sin asignar)' : colorName),
          const SizedBox(height: 8),
          _DisplayRow(
              label: 'Cuadrilla',
              value: widget.cuadrilla?.isEmpty ?? true
                  ? '(Sin asignar)'
                  : widget.cuadrilla!),
          const SizedBox(height: 8),
          _DisplayRow(
              label: 'Lote',
              value: _loteCtrl.text.isEmpty ? '(Sin asignar)' : _loteCtrl.text),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 120,
                child: Text('Recusado',
                    style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              if (_recusado) ...[
                Checkbox(value: true, onChanged: null),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _recusadoDescCtrl.text.isEmpty
                        ? '(Sin descripción)'
                        : _recusadoDescCtrl.text,
                    style: TextStyle(
                      color: _recusadoDescCtrl.text.isEmpty
                          ? Colors.grey
                          : Colors.black,
                    ),
                  ),
                ),
              ] else
                Checkbox(value: false, onChanged: null),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _isEditing = true),
                icon: const Icon(Icons.edit),
                label: const Text('Editar'),
              ),
              IconButton(
                tooltip: 'Eliminar',
                onPressed: _delete,
                icon: const Icon(Icons.delete, color: Colors.red),
              ),
            ],
          ),
        ],
      );
    }

    // Modo edición
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ColorPickerWidget(
          initialColor: _selectedColor,
          onColorSelected: (color) => setState(() => _selectedColor = color),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey.shade100,
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 100,
                child: Text('Cuadrilla',
                    style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.cuadrilla?.isEmpty ?? true
                      ? '(Sin asignar)'
                      : widget.cuadrilla!,
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _loteCtrl,
          decoration: InputDecoration(
            labelText: 'Lote',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Checkbox(
              value: _recusado,
              onChanged: (value) => setState(() => _recusado = value ?? false),
            ),
            const Text('Recusado'),
          ],
        ),
        if (_recusado) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _recusadoDescCtrl,
            maxLines: 3,
            maxLength: 140,
            decoration: InputDecoration(
              labelText: 'Razón del rechazo',
              hintText: 'Describe por qué fue recusado',
              counterText: '',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() {
                _isEditing = false;
                _loteCtrl.text = widget.lote ?? '';
                _recusado = widget.recusado;
                _recusadoDescCtrl.text = widget.recusadoDesc ?? '';
                _selectedColor = widget.cintaColor;
              }),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Guardar'),
            ),
          ],
        ),
      ],
    );
  }
}

class _DisplayRow extends StatelessWidget {
  final String label;
  final String value;

  const _DisplayRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}

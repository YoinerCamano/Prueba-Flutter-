import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/firebase_provider.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../widgets/bunch_colors.dart';

class BunchTablePage extends StatefulWidget {
  final String? deviceId;
  const BunchTablePage({super.key, this.deviceId});

  @override
  State<BunchTablePage> createState() => _BunchTablePageState();
}

class _BunchTablePageState extends State<BunchTablePage> {
  late final conn.ConnectionBloc _connectionBloc;
  String? _tableId;

  @override
  void initState() {
    super.initState();
    _connectionBloc = context.read<conn.ConnectionBloc>();
    // Pausar polling al entrar
    _connectionBloc.add(conn.StopPolling());

    // Diferir la inicialización para permitir que el contexto esté completamente listo
    Future.delayed(Duration.zero, _initTable);
  }

  @override
  void dispose() {
    // Reanudar polling al salir
    _connectionBloc.add(conn.StartPolling());
    super.dispose();
  }

  Future<void> _initTable() async {
    if (!mounted) return;
    try {
      final firebaseService = FirebaseProvider.of(context);
      String? deviceId = widget.deviceId;
      final state = _connectionBloc.state;
      if (deviceId == null && state is conn.Connected) {
        deviceId = state.device.id;
      }
      if (deviceId == null) return;
      final id =
          await firebaseService.getOrCreateTodayBunchTable(deviceId: deviceId);
      if (mounted) {
        setState(() => _tableId = id);
      }
    } catch (e) {
      print('Error iniciando tabla: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tabla de Racimos (Diaria)'),
      ),
      body: _tableId == null
          ? const Center(child: CircularProgressIndicator())
          : _BunchEntriesList(tableId: _tableId!),
    );
  }
}

class _BunchEntriesList extends StatelessWidget {
  final String tableId;
  const _BunchEntriesList({required this.tableId});

  @override
  Widget build(BuildContext context) {
    final firebaseService = FirebaseProvider.of(context);
    return StreamBuilder(
      stream: firebaseService.streamBunchEntriesByTable(tableId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!;
        if (docs.isEmpty) {
          return const Center(child: Text('Sin racimos aún'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final d = docs[index].data();
            final entryId = docs[index].id;
            final number = d['number'] ?? index + 1;
            final weightKg = (d['weightKg'] ?? 0).toDouble();
            final weighingTime = d['weighingTime'];
            final cintaColor = d['cintaColor'] as String?;
            final cuadrilla = d['cuadrilla'] as String?;
            final lote = d['lote'] as String?;
            final recusado = (d['recusado'] ?? false) as bool;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('#$number',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        Text('Peso: ${weightKg.toStringAsFixed(2)} kg'),
                        const Spacer(),
                        Text(
                          weighingTime != null
                              ? DateTime.parse(weighingTime.toDate().toString())
                                  .toLocal()
                                  .toString()
                              : '',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _EditableFieldsRow(
                      entryId: entryId,
                      cintaColor: cintaColor,
                      cuadrilla: cuadrilla,
                      lote: lote,
                      recusado: recusado,
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
}

class _EditableFieldsRow extends StatefulWidget {
  final String entryId;
  final String? cintaColor;
  final String? cuadrilla;
  final String? lote;
  final bool recusado;

  const _EditableFieldsRow({
    required this.entryId,
    this.cintaColor,
    this.cuadrilla,
    this.lote,
    required this.recusado,
  });

  @override
  State<_EditableFieldsRow> createState() => _EditableFieldsRowState();
}

class _EditableFieldsRowState extends State<_EditableFieldsRow> {
  late TextEditingController _cuadrillaCtrl;
  late TextEditingController _loteCtrl;
  late bool _recusado;
  String? _selectedColor;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _cuadrillaCtrl = TextEditingController(text: widget.cuadrilla ?? '');
    _loteCtrl = TextEditingController(text: widget.lote ?? '');
    _recusado = widget.recusado;
    _selectedColor = widget.cintaColor;
  }

  @override
  void dispose() {
    _cuadrillaCtrl.dispose();
    _loteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final firebaseService = FirebaseProvider.of(context);
    try {
      await firebaseService.updateBunchEntryFields(
        entryId: widget.entryId,
        cintaColor: _selectedColor?.trim().isEmpty ?? true
            ? null
            : _selectedColor?.trim(),
        cuadrilla: _cuadrillaCtrl.text.trim().isEmpty
            ? null
            : _cuadrillaCtrl.text.trim(),
        lote: _loteCtrl.text.trim().isEmpty ? null : _loteCtrl.text.trim(),
        recusado: _recusado,
      );
      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Cambios guardados')),
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

  Future<void> _delete() async {
    final firebaseService = FirebaseProvider.of(context);
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
        await firebaseService.deleteBunchEntry(entryId: widget.entryId);
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
              value: _cuadrillaCtrl.text.isEmpty
                  ? '(Sin asignar)'
                  : _cuadrillaCtrl.text),
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
              Checkbox(value: _recusado, onChanged: null),
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
        TextField(
          controller: _cuadrillaCtrl,
          decoration: InputDecoration(
            labelText: 'Cuadrilla',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() {
                _isEditing = false;
                _cuadrillaCtrl.text = widget.cuadrilla ?? '';
                _loteCtrl.text = widget.lote ?? '';
                _recusado = widget.recusado;
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

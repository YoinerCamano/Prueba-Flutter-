import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/firebase_provider.dart';
import '../blocs/connection/connection_bloc.dart' as conn;

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
    _initTable();
  }

  @override
  void dispose() {
    // Reanudar polling al salir
    _connectionBloc.add(conn.StartPolling());
    super.dispose();
  }

  Future<void> _initTable() async {
    final firebaseService = FirebaseProvider.of(context);
    String? deviceId = widget.deviceId;
    final state = _connectionBloc.state;
    if (deviceId == null && state is conn.Connected) {
      deviceId = state.device.id;
    }
    if (deviceId == null) return;
    final id =
        await firebaseService.getOrCreateTodayBunchTable(deviceId: deviceId);
    setState(() => _tableId = id);
  }

  Future<void> _addEntry() async {
    if (_tableId == null) return;
    final firebaseService = FirebaseProvider.of(context);
    final now = DateTime.now();
    // Calcular número siguiente basado en cantidad actual
    // Para simplicidad, se usará timestamp como incremental visual
    await firebaseService.addBunchEntry(
      tableId: _tableId!,
      number: now.millisecondsSinceEpoch, // placeholder incremental
      weightKg: 0,
      weighingTime: now,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tabla de Racimos (Diaria)'),
        actions: [
          IconButton(
            tooltip: 'Agregar Racimo',
            onPressed: _addEntry,
            icon: const Icon(Icons.add),
          )
        ],
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
  late TextEditingController _cintaCtrl;
  late TextEditingController _cuadrillaCtrl;
  late TextEditingController _loteCtrl;
  late bool _recusado;

  @override
  void initState() {
    super.initState();
    _cintaCtrl = TextEditingController(text: widget.cintaColor ?? '');
    _cuadrillaCtrl = TextEditingController(text: widget.cuadrilla ?? '');
    _loteCtrl = TextEditingController(text: widget.lote ?? '');
    _recusado = widget.recusado;
  }

  @override
  void dispose() {
    _cintaCtrl.dispose();
    _cuadrillaCtrl.dispose();
    _loteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final firebaseService = FirebaseProvider.of(context);
    await firebaseService.updateBunchEntryFields(
      entryId: widget.entryId,
      cintaColor:
          _cintaCtrl.text.trim().isEmpty ? null : _cintaCtrl.text.trim(),
      cuadrilla: _cuadrillaCtrl.text.trim().isEmpty
          ? null
          : _cuadrillaCtrl.text.trim(),
      lote: _loteCtrl.text.trim().isEmpty ? null : _loteCtrl.text.trim(),
      recusado: _recusado,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cambios guardados')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cintaCtrl,
                decoration: const InputDecoration(labelText: 'Color de cinta'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _cuadrillaCtrl,
                decoration: const InputDecoration(labelText: 'Cuadrilla'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _loteCtrl,
                decoration: const InputDecoration(labelText: 'Lote'),
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: [
                Switch(
                  value: _recusado,
                  onChanged: (v) => setState(() => _recusado = v),
                ),
                const Text('Recusado'),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
          ],
        ),
      ],
    );
  }
}

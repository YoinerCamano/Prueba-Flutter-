import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../widgets/firebase_widgets.dart';

enum DateFilter { none, today, thisMonth, custom }

/// Página para ver el historial de pesajes con filtros
class WeighingHistoryPage extends StatefulWidget {
  const WeighingHistoryPage({super.key});

  @override
  State<WeighingHistoryPage> createState() => _WeighingHistoryPageState();
}

class _WeighingHistoryPageState extends State<WeighingHistoryPage> {
  String? _selectedDeviceId;
  int _limit = 50;
  DateFilter _dateFilter = DateFilter.none;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  DateTime? get _effectiveStartDate {
    switch (_dateFilter) {
      case DateFilter.today:
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day);
      case DateFilter.thisMonth:
        final now = DateTime.now();
        return DateTime(now.year, now.month, 1);
      case DateFilter.custom:
        return _customStartDate;
      case DateFilter.none:
        return null;
    }
  }

  DateTime? get _effectiveEndDate {
    switch (_dateFilter) {
      case DateFilter.today:
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case DateFilter.thisMonth:
        final now = DateTime.now();
        return DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      case DateFilter.custom:
        return _customEndDate;
      case DateFilter.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final connState = context.read<conn.ConnectionBloc>().state;

    // Obtener deviceId actual si está conectado
    if (_selectedDeviceId == null && connState is conn.Connected) {
      _selectedDeviceId = connState.device.id;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Pesajes'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Cantidad a mostrar',
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _limit = value;
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 20,
                child: Text(
                  'Últimos 20',
                  style: TextStyle(
                    fontWeight: _limit == 20 ? FontWeight.bold : null,
                  ),
                ),
              ),
              PopupMenuItem(
                value: 50,
                child: Text(
                  'Últimos 50',
                  style: TextStyle(
                    fontWeight: _limit == 50 ? FontWeight.bold : null,
                  ),
                ),
              ),
              PopupMenuItem(
                value: 100,
                child: Text(
                  'Últimos 100',
                  style: TextStyle(
                    fontWeight: _limit == 100 ? FontWeight.bold : null,
                  ),
                ),
              ),
              PopupMenuItem(
                value: 200,
                child: Text(
                  'Últimos 200',
                  style: TextStyle(
                    fontWeight: _limit == 200 ? FontWeight.bold : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtros
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filtros',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  // Filtro por dispositivo
                  Row(
                    children: [
                      const Icon(Icons.bluetooth, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dispositivo: ${_selectedDeviceId ?? "Todos"}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      if (_selectedDeviceId != null)
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedDeviceId = null;
                            });
                          },
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Limpiar'),
                        ),
                    ],
                  ),
                  const Divider(),

                  // Filtro por fecha
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16),
                      const SizedBox(width: 8),
                      const Text('Fecha:', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('Todas'),
                        selected: _dateFilter == DateFilter.none,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _dateFilter = DateFilter.none;
                            });
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Hoy'),
                        selected: _dateFilter == DateFilter.today,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _dateFilter = DateFilter.today;
                            });
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Este mes'),
                        selected: _dateFilter == DateFilter.thisMonth,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _dateFilter = DateFilter.thisMonth;
                            });
                          }
                        },
                      ),
                    ],
                  ),

                  // Botón de rango personalizado
                  if (_dateFilter == DateFilter.none)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton.icon(
                        onPressed: () => _selectCustomDateRange(context),
                        icon: const Icon(Icons.date_range, size: 16),
                        label: const Text('Rango personalizado'),
                      ),
                    ),

                  // Mostrar rango personalizado seleccionado
                  if (_dateFilter == DateFilter.custom &&
                      _customStartDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Desde ${_formatDate(_customStartDate!)} hasta ${_customEndDate != null ? _formatDate(_customEndDate!) : "hoy"}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              setState(() {
                                _dateFilter = DateFilter.none;
                                _customStartDate = null;
                                _customEndDate = null;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                  const Divider(),
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Mostrando últimos $_limit registros',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Lista de pesajes
          Expanded(
            child: MeasurementHistoryWidget(
              sessionId: null,
              deviceId: _selectedDeviceId,
              startDate: _effectiveStartDate,
              endDate: _effectiveEndDate,
              limit: _limit,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectCustomDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _dateFilter = DateFilter.custom;
        _customStartDate = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
        _customEndDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities.dart';
import '../../data/local/database_service.dart';
import '../../core/database_provider.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../blocs/scan/scan_cubit.dart';
import '../widgets/device_tile.dart';
import '../widgets/weight_card.dart';
import '../widgets/scan_devices_dialog.dart';
import '../widgets/sqlite_widgets.dart';
import '../widgets/bunch_colors.dart';
import 'device_info_page.dart';
import 'configuration_page.dart';
import 'weighing_history_page.dart';
import 'bunch_table_page.dart';
// import '../widgets/device_info_loader.dart'; // Reemplazado por DeviceInfoPage
// import '../widgets/device_info_card.dart'; // Reemplazado por DeviceInfoLoader
// import '../widgets/scale_status_icon.dart'; // DESACTIVADO
// import '../widgets/device_info_widget.dart'; // Reemplazado por DeviceInfoCard

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Controla si el diálogo de "Conectando" está abierto
  bool _connectingDialogOpen = false;

  // Catálogos para el guardado de pesajes
  List<Cuadrilla> _cuadrillas = [];
  List<Operario> _operarios = [];
  int? _selectedCuadrillaId;
  int? _selectedOperarioId;
  int? _selectedBasculaId;
  int? _activeTripId;
  String? _selectedColorCinta;
  bool _autoSaveEnabled = false;
  bool _manualSaveEnabled = true;
  double _minimumSaveWeight = 1.0;
  double _unloadThreshold = 0.5;
  bool _autoSavePaused = false;
  bool _currentBunchSaved = false;
  bool _savingInProgress = false;
  DatabaseService? _databaseService;

  // Control para evitar mostrar múltiples veces el diálogo de báscula no registrada
  bool _basculaDialogShown = false;

  // Control para evitar buscar báscula múltiples veces por el mismo dispositivo
  String? _lastDeviceMacSearched;

  @override
  void initState() {
    super.initState();
    print('🏠 === INICIALIZANDO HOME PAGE ===');
    print('📱 Cargando dispositivos vinculados automáticamente...');
    context.read<ScanCubit>().loadBonded();

    // Verificar si ya hay una conexión activa al iniciar
    print('🔍 Verificando conexión automática...');
    context
        .read<conn.ConnectionBloc>()
        .add(conn.CheckAutoConnectionRequested());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _databaseService ??= DatabaseProvider.of(context);
    // Cargar/recargar catálogos cuando DatabaseService esté disponible
    if (_databaseService != null) {
      _loadCatalogs();
      _loadPreferredColor();
      _loadSaveRules();
    }
  }

  Future<void> _loadPreferredColor() async {
    final db = DatabaseProvider.of(context);
    final saved = await db.getPreferredColor();
    if (mounted) {
      setState(() {
        // Si no hay guardado, usar Blanco como default
        _selectedColorCinta = saved ?? BunchColors.white;
      });
    }
  }

  Future<void> _loadSaveRules() async {
    final db = DatabaseProvider.of(context);
    final autoSaveEnabled = await db.getAutoSaveEnabled();
    final manualSaveEnabled = await db.getManualSaveEnabled();
    final minimumSaveWeight = await db.getMinimumSaveWeight();
    final unloadThreshold = await db.getUnloadThreshold();

    if (!mounted) return;
    setState(() {
      _autoSaveEnabled = autoSaveEnabled;
      _manualSaveEnabled = manualSaveEnabled;
      _minimumSaveWeight = minimumSaveWeight;
      _unloadThreshold = unloadThreshold;
    });
  }

  Future<void> _refreshActiveTrip() async {
    var basculaId = _selectedBasculaId;
    if (basculaId == null) {
      if (mounted) {
        setState(() => _activeTripId = null);
      }
      return;
    }

    final db = DatabaseProvider.of(context);
    final viaje = await db.obtenerViajeActivoPorBascula(basculaId);
    if (!mounted) return;
    setState(() {
      _activeTripId = viaje == null ? null : viaje['id_viaje'] as int?;
    });
  }

  Future<void> _loadCatalogs() async {
    final db = _databaseService;
    if (db == null) return;
    try {
      final cuadrillaRows = await db.getCuadrillas();
      final operarioRows = await db.getOperarios();
      setState(() {
        _cuadrillas = cuadrillaRows.map((r) => Cuadrilla.fromMap(r)).toList()
          ..sort((a, b) => a.nombre.compareTo(b.nombre));
        _operarios = operarioRows.map((r) => Operario.fromMap(r)).toList()
          ..sort((a, b) => a.nombreCompleto.compareTo(b.nombreCompleto));

        // Validar que la cuadrilla seleccionada siga existiendo
        if (_selectedCuadrillaId != null &&
            !_cuadrillas.any((c) => c.idCuadrilla == _selectedCuadrillaId)) {
          _selectedCuadrillaId = null;
          _selectedOperarioId = null;
        }

        // Validar que el operario seleccionado siga existiendo
        if (_selectedOperarioId != null &&
            !_operarios.any((o) => o.idOperario == _selectedOperarioId)) {
          _selectedOperarioId = null;
        }

        // Auto-seleccionar primera cuadrilla si no hay ninguna seleccionada
        if (_cuadrillas.isNotEmpty && _selectedCuadrillaId == null) {
          _selectedCuadrillaId = _cuadrillas.first.idCuadrilla;
          _filterOperarios();
        }
        // NO auto-seleccionar báscula - solo se selecciona cuando se conecta por MAC
      });
    } catch (e) {
      print('Error cargando catálogos: $e');
    }
  }

  Future<void> _refreshCatalogsAndBascula() async {
    await _loadCatalogs();
    if (!mounted) return;

    // Permite reintentar lookup de la MAC conectada después de cambios en catálogo.
    _lastDeviceMacSearched = null;

    final currentState = context.read<conn.ConnectionBloc>().state;
    if (currentState is conn.Connected) {
      await _autoSelectBasculaByMac(context, currentState);
    }
  }

  void _filterOperarios() {
    // Solo mostrar operarios de la cuadrilla seleccionada
    if (_selectedCuadrillaId == null) {
      setState(() => _selectedOperarioId = null);
      return;
    }
    final filtered =
        _operarios.where((o) => o.idCuadrilla == _selectedCuadrillaId).toList();
    setState(() {
      _selectedOperarioId =
          filtered.isNotEmpty ? filtered.first.idOperario : null;
    });
  }

  /// Auto-seleccionar báscula basada en la MAC del dispositivo conectado
  Future<void> _autoSelectBasculaByMac(
      BuildContext context, conn.Connected state) async {
    final db = _databaseService;
    if (db == null) return;

    try {
      // Obtener la MAC del dispositivo conectado
      final deviceMac = state.device.id;
      if (deviceMac.isEmpty) {
        print('⚠️  No hay MAC de dispositivo disponible');
        return;
      }

      // Evitar consultas repetidas solo si ya hay una báscula seleccionada.
      // Si no hay selección, permitir reintento (ej. después de registrarla en Configuración).
      if (_lastDeviceMacSearched == deviceMac && _selectedBasculaId != null) {
        print('ℹ️  Báscula ya seleccionada para esta MAC');
        return;
      }

      _lastDeviceMacSearched = deviceMac;
      print('🔍 Buscando báscula con MAC: $deviceMac');

      // Buscar la báscula en la BD
      final bascula = await db.getBasculaByMac(deviceMac);

      if (bascula != null) {
        // Báscula encontrada - auto-seleccionar
        print('✅ Báscula encontrada: ${bascula.nombre}');
        setState(() {
          _selectedBasculaId = bascula.idBascula;
          _basculaDialogShown = false; // Resetear el flag
        });
        unawaited(_refreshActiveTrip());
      } else {
        // Báscula NO encontrada - NO auto-seleccionar
        print('❌ Báscula NO registrada con MAC: $deviceMac');
        // No mostrar mensaje aquí, dejamos que aparezca cuando intente guardar
      }
    } catch (e) {
      print('Error auto-seleccionando báscula: $e');
    }
  }

  /// Mostrar diálogo de advertencia cuando la báscula no está registrada
  void _showBasculaNotRegisteredDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.orange,
          size: 64,
        ),
        title: const Text(
          'Báscula No Registrada',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'La báscula conectada no está registrada en el sistema.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'MAC: ${context.read<conn.ConnectionBloc>().state is conn.Connected ? (context.read<conn.ConnectionBloc>().state as conn.Connected).device.id : "Desconocido"}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Por favor, registre la báscula en la sección de Configuración antes de poder guardar pesajes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCELAR'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ConfigurationPage(),
                ),
              );
            },
            icon: const Icon(Icons.settings),
            label: const Text('IR A CONFIGURACIÓN'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return BlocListener<conn.ConnectionBloc, conn.ConnectionState>(
      listener: (context, state) {
        // Mostrar dialog de conexión cuando está conectando
        if (state is conn.Connecting) {
          // Evitar abrir múltiples veces
          if (!_connectingDialogOpen) {
            _connectingDialogOpen = true;
          }
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => _buildConnectingDialog(state),
          );
        } else if (state is conn.Connected) {
          // Cerrar el diálogo si estaba abierto
          if (_connectingDialogOpen) {
            _connectingDialogOpen = false;
            Navigator.of(context, rootNavigator: true).pop();
          }
          // Auto-seleccionar báscula basada en la MAC conectada
          _autoSelectBasculaByMac(context, state);
        } else {
          // Cerrar el diálogo sólo si lo abrimos desde esta pantalla
          if (_connectingDialogOpen) {
            _connectingDialogOpen = false;
            // Usar rootNavigator para asegurarnos de cerrar el diálogo modal
            Navigator.of(context, rootNavigator: true).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Módulo Pesaje'),
          actions: [
            IconButton(
              tooltip: 'Historial de Pesajes',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WeighingHistoryPage(),
                  ),
                );
              },
              icon: const Icon(Icons.history),
            ),
            // Tabla diaria de racimos
            IconButton(
              tooltip: 'Tabla de Racimos',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BunchTablePage(),
                  ),
                );
              },
              icon: const Icon(Icons.table_chart),
            ),
            BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
              builder: (context, connectionState) {
                if (connectionState is conn.Connected) {
                  return IconButton(
                    tooltip: 'Acerca del dispositivo',
                    onPressed: () => _showDeviceInfo(context, connectionState),
                    icon: const Icon(Icons.info_outline),
                  );
                }
                return const SizedBox
                    .shrink(); // No mostrar si no está conectado
              },
            ),
            // ⚙️ Icono de configuración
            BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
              builder: (context, connectionState) {
                if (connectionState is conn.Connected) {
                  return IconButton(
                    tooltip: 'Configuración',
                    onPressed: () =>
                        _showConfiguration(context, connectionState),
                    icon: const Icon(Icons.settings),
                  );
                }
                return const SizedBox
                    .shrink(); // No mostrar si no está conectado
              },
            ),
            IconButton(
              tooltip: 'Buscar dispositivos',
              onPressed: () => _showScanDialog(),
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        body: SafeArea(
          child: BlocConsumer<conn.ConnectionBloc, conn.ConnectionState>(
            buildWhen: (prev, curr) {
              // No reconstruir el layout por cambios de peso — WeightCard lo maneja solo
              if (prev is conn.Connected && curr is conn.Connected) {
                return prev.device.id != curr.device.id ||
                    prev.weightUnit != curr.weightUnit;
              }
              return prev.runtimeType != curr.runtimeType;
            },
            listener: (context, state) {
              if (state is conn.ConnectionError) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message)));
              }

              // Detener escaneo cuando se conecta exitosamente
              if (state is conn.Connected) {
                context.read<ScanCubit>().stopScanning();
                _handleAutoSave(state);
                print('🛑 Escaneo detenido - dispositivo conectado');
              }
            },
            builder: (context, connState) {
              final connectedState =
                  connState is conn.Connected ? connState : null;
              final connecting = connState is conn.Connecting;

              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // === Tarjeta de lectura de peso o mensaje vacío ===
                    if (connectedState != null)
                      const WeightCard()
                    else if (!connecting)
                      Card(
                        color: color.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'No hay dispositivo conectado. Selecciona uno para iniciar.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // === Dropdowns de Cuadrilla, Operario y Bascula (Fila Horizontal) ===
                    if (connectedState != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade400,
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: DropdownButton<int>(
                                  isExpanded: true,
                                  isDense: false,
                                  elevation: 8,
                                  underline: const SizedBox(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  hint: const Text('Cuadrilla'),
                                  value: _selectedCuadrillaId,
                                  dropdownColor: Colors.white,
                                  items: _cuadrillas
                                      .map((c) => DropdownMenuItem(
                                            value: c.idCuadrilla,
                                            child: Text(c.nombre),
                                          ))
                                      .toList(),
                                  onChanged: (id) {
                                    if (id != null) {
                                      setState(() {
                                        _selectedCuadrillaId = id;
                                        _filterOperarios();
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade400,
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: DropdownButton<int>(
                                  isExpanded: true,
                                  isDense: false,
                                  elevation: 8,
                                  underline: const SizedBox(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  hint: const Text('Operario'),
                                  value: _selectedOperarioId,
                                  dropdownColor: Colors.white,
                                  items: _selectedCuadrillaId == null
                                      ? []
                                      : _operarios
                                          .where((o) =>
                                              o.idCuadrilla ==
                                              _selectedCuadrillaId)
                                          .map((o) => DropdownMenuItem(
                                                value: o.idOperario,
                                                child: Text(o.nombreCompleto),
                                              ))
                                          .toList(),
                                  onChanged: (id) {
                                    if (id != null) {
                                      setState(() => _selectedOperarioId = id);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: 'Actualizar catálogos',
                              onPressed: () {
                                unawaited(_refreshCatalogsAndBascula());
                              },
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // === Selector de color de cinta ===
                    if (connectedState != null)
                      ColorPickerWidget(
                        initialColor: _selectedColorCinta,
                        onColorSelected: (color) {
                          setState(() => _selectedColorCinta = color);
                          unawaited(
                            DatabaseProvider.of(context)
                                .setPreferredColor(color),
                          );
                        },
                      ),

                    const SizedBox(height: 16),

                    // === Botones de acción horizontal: GUARDAR PESAJE ===
                    if (connectedState != null)
                      BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
                        builder: (context, connState) {
                          final current =
                              connState is conn.Connected ? connState : null;
                          final isStable =
                              current?.weight?.status == WeightStatus.stable;
                          final currentWeight = current?.weight?.kg ?? 0;
                          final meetsMinimumWeight =
                              currentWeight >= _minimumSaveWeight;
                          final canSave = _manualSaveEnabled &&
                              !_savingInProgress &&
                              !_currentBunchSaved &&
                              isStable &&
                              meetsMinimumWeight &&
                              _selectedCuadrillaId != null &&
                              _selectedOperarioId != null &&
                              _selectedBasculaId != null;

                          return Row(
                            children: [
                              if (_autoSaveEnabled) ...[
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _savingInProgress
                                        ? null
                                        : () => setState(
                                              () => _autoSavePaused =
                                                  !_autoSavePaused,
                                            ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _autoSavePaused
                                          ? Colors.green
                                          : Colors.orange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                    icon: Icon(
                                      _autoSavePaused
                                          ? Icons.play_arrow
                                          : Icons.pause,
                                      size: 20,
                                    ),
                                    label: Text(
                                      _autoSavePaused
                                          ? 'Reanudar operación'
                                          : 'Pausar operación',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed:
                                        _savingInProgress ? null : _closeActiveTrip,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                    icon: const Icon(Icons.flag_outlined),
                                    label: const Text('Finalizar viaje'),
                                  ),
                                ),
                              ] else ...[
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: canSave
                                        ? () => _saveWeighing(
                                            context, current ?? connectedState)
                                        : null,
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          canSave ? Colors.blue : Colors.grey,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                    ),
                                    icon: const Icon(Icons.save, size: 20),
                                    label: Text(
                                      !isStable
                                          ? 'Esperando...'
                                          : !_manualSaveEnabled
                                              ? 'Guardado manual desactivado'
                                              : _savingInProgress
                                                  ? 'Guardando...'
                                                  : _currentBunchSaved
                                                      ? 'Descargue para nuevo guardado'
                                                      : !meetsMinimumWeight
                                                          ? 'Mínimo ${_minimumSaveWeight.toStringAsFixed(2)}'
                                                          : _selectedCuadrillaId ==
                                                                  null
                                                              ? 'Selecciona cuadrilla'
                                                              : _selectedOperarioId ==
                                                                      null
                                                                  ? 'Selecciona operario'
                                                                  : _selectedBasculaId ==
                                                                          null
                                                                      ? 'Báscula no registrada'
                                                                      : 'GUARDAR',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed:
                                        _savingInProgress ? null : _closeActiveTrip,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                    icon: const Icon(Icons.flag_outlined),
                                    label: const Text('Finalizar viaje'),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),

                    const SizedBox(height: 16),

                    // === Últimos 5 pesajes ===
                    if (connectedState != null)
                      BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
                        buildWhen: (previous, current) {
                          // Solo reconstruir cuando cambie el dispositivo conectado
                          // No reconstruir en cada actualización de peso
                          if (previous is conn.Connected &&
                              current is conn.Connected) {
                            return previous.device.id != current.device.id;
                          }
                          return previous.runtimeType != current.runtimeType;
                        },
                        builder: (context, connState) {
                          if (connState is! conn.Connected) {
                            return const SizedBox.shrink();
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.history, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      _activeTripId == null
                                          ? 'Últimos pesajes (sin viaje activo)'
                                          : 'Últimos pesajes del viaje',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const WeighingHistoryPage(),
                                          ),
                                        );
                                      },
                                      child: const Text('Ver todos'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_activeTripId == null)
                                const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: Text(
                                    'No hay viaje activo para mostrar pesajes.',
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              else
                                SizedBox(
                                  height: 200,
                                  child: BunchHistoryWidget(
                                    limit: 5,
                                    filters: BunchFilters(idViaje: _activeTripId),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),

                    const SizedBox(height: 16),

                    // === Lista de dispositivos vinculados/emparejados únicamente ===
                    if (connectedState == null && !connecting) ...[
                      Row(
                        children: [
                          Text(
                            'Dispositivos Emparejados',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          // Botón principal de actualizar
                          TextButton.icon(
                            onPressed: () =>
                                context.read<ScanCubit>().loadBonded(),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Actualizar'),
                          ),
                          // Menú desplegable para acciones adicionales
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              switch (value) {
                                case 'manual':
                                  _checkManualConnection();
                                  break;
                                case 'diagnostic':
                                  _runDiagnostic();
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'manual',
                                child: Row(
                                  children: [
                                    Icon(Icons.bluetooth_connected, size: 16),
                                    SizedBox(width: 8),
                                    Text('Verificar Manual'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'diagnostic',
                                child: Row(
                                  children: [
                                    Icon(Icons.bug_report, size: 16),
                                    SizedBox(width: 8),
                                    Text('Diagnóstico'),
                                  ],
                                ),
                              ),
                            ],
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.more_vert),
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: BlocBuilder<ScanCubit, ScanState>(
                          builder: (context, scanState) {
                            print(
                                '🎨 === UI REBUILD DISPOSITIVOS EMPAREJADOS ===');
                            print(
                                '📊 Dispositivos vinculados: ${scanState.bonded.length}');

                            final items = <Widget>[];

                            // Mostrar SOLO dispositivos vinculados/emparejados
                            for (final d in scanState.bonded) {
                              print(
                                  '🎨 Agregando emparejado: ${d.name} (${d.id})');
                              items.add(
                                DeviceTile(
                                  device: d,
                                  onTap: () => _connect(d),
                                ),
                              );
                              items.add(const Divider(height: 1));
                            }

                            if (items.isEmpty) {
                              print('⚠️ UI: Lista vacía, mostrando mensaje');
                              items.add(
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.bluetooth_disabled,
                                          size: 48,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No hay dispositivos emparejados',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Usa el botón de búsqueda para encontrar nuevos dispositivos',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline,
                                              ),
                                        ),
                                        const SizedBox(height: 16),
                                        FilledButton.icon(
                                          onPressed: () => _showScanDialog(),
                                          icon: const Icon(Icons.search,
                                              size: 18),
                                          label:
                                              const Text('Buscar Dispositivos'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              print(
                                  '✅ UI: Mostrando ${items.length ~/ 2} dispositivos emparejados');
                            }

                            return ListView(children: items);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 🔄 Widget para mostrar el dialog de conexión centrado
  Widget _buildConnectingDialog(conn.Connecting state) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icono animado de Bluetooth
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bluetooth_searching,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),

            // Indicador de progreso
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Título
            Text(
              'Conectando',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 12),

            // Nombre del dispositivo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.scale,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      state.device.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Mensaje descriptivo
            Text(
              'Estableciendo conexión Bluetooth...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Por favor espera un momento',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.7),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _runDiagnostic() async {
    print('🔍 === DIAGNÓSTICO BLUETOOTH ===');
    // Funcionalidad de diagnóstico deshabilitada temporalmente
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ Diagnóstico no disponible en esta versión'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _connect(BtDevice d) {
    print('🔗 === INICIANDO CONEXIÓN DESDE UI ===');
    print('🎯 Dispositivo seleccionado: ${d.name} (${d.id})');
    context.read<conn.ConnectionBloc>().add(conn.ConnectRequested(d));
  }

  void _checkManualConnection() {
    // Buscar la S3 específica en los dispositivos emparejados
    final scanState = context.read<ScanCubit>().state;

    // Buscar la S3 por dirección MAC conocida
    final s3Device = scanState.bonded
        .where((device) =>
            device.id == 'DE:FD:76:A4:D7:ED' ||
            device.name.contains('S3') ||
            device.name.contains('680066'))
        .firstOrNull;

    if (s3Device != null) {
      print('🔍 Verificando conexión manual para S3: ${s3Device.name}');
      context
          .read<conn.ConnectionBloc>()
          .add(conn.CheckManualConnectionRequested(s3Device));

      // Mostrar mensaje informativo
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔍 Verificando si hay una conexión manual activa...'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // Si no encontramos la S3, mostrar mensaje y ofrecer actualizar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '⚠️ S3 no encontrada en dispositivos emparejados. Actualiza la lista.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _handleAutoSave(conn.Connected state) {
    final weightKg = state.weight?.kg ?? 0;

    if (_currentBunchSaved && weightKg < _unloadThreshold) {
      setState(() {
        _currentBunchSaved = false;
      });
      return;
    }

    final isStable = state.weight?.status == WeightStatus.stable;
    final hasMinimumWeight = weightKg >= _minimumSaveWeight;
    final hasRequiredData = _selectedCuadrillaId != null &&
        _selectedOperarioId != null &&
        _selectedBasculaId != null;

    if (_autoSaveEnabled &&
        !_autoSavePaused &&
        !_savingInProgress &&
        !_currentBunchSaved &&
        isStable &&
        hasMinimumWeight &&
        hasRequiredData) {
      unawaited(_saveWeighing(context, state, isAutoSave: true));
    }
  }

  Future<void> _closeActiveTrip() async {
    var basculaId = _selectedBasculaId;
    if (basculaId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ No hay báscula seleccionada para cerrar viaje.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      final db = DatabaseProvider.of(context);
      final viaje = await db.obtenerViajeActivoPorBascula(basculaId);
      if (viaje == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ℹ️ No hay viaje activo en esta báscula.'),
            ),
          );
        }
        return;
      }

      final idViaje = viaje['id_viaje'] as int;
      await db.finalizarViajePesaje(idViaje: idViaje);
      if (mounted) {
        setState(() {
          _currentBunchSaved = false;
          _activeTripId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Viaje finalizado correctamente.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al finalizar viaje: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 💾 Guardar pesaje local
  Future<bool> _saveWeighing(
    BuildContext context,
    conn.Connected state, {
    bool isAutoSave = false,
  }) async {
    if (_savingInProgress) return false;
    _savingInProgress = true;

    final weight = state.weight;
    final weightKg = weight?.kg;
    final weightUnit = (state.weightUnit == 'lb') ? 'lb' : 'kg';
    final cuadrillaId = _selectedCuadrillaId;
    final operarioId = _selectedOperarioId;
    var basculaId = _selectedBasculaId;
    final colorCinta = _selectedColorCinta;

    if (weightKg == null || cuadrillaId == null || operarioId == null) {
      _savingInProgress = false;
      return false;
    }

    if (_currentBunchSaved) {
      _savingInProgress = false;
      return false;
    }

    if (weightKg < _minimumSaveWeight) {
      _savingInProgress = false;
      return false;
    }

    if (weightKg <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ El peso debe ser mayor a 0 para guardar.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      _savingInProgress = false;
      return false;
    }

    // Reintentar autoselección por MAC antes de bloquear el guardado.
    if (basculaId == null) {
      await _autoSelectBasculaByMac(context, state);
      basculaId = _selectedBasculaId;
    }

    // Verificar que la báscula esté registrada
    if (basculaId == null) {
      if (!_basculaDialogShown) {
        _basculaDialogShown = true;
        _showBasculaNotRegisteredDialog(context);
      }
      _savingInProgress = false;
      return false;
    }

    // Reiniciar el flag cuando se guarde correctamente
    _basculaDialogShown = false;

    // ✅ Mostrar confirmación INMEDIATA
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${isAutoSave ? '✅ Auto guardando' : '✅ Guardando'}: ${weightKg.toStringAsFixed(2)} $weightUnit',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    }

    try {
      final databaseService = DatabaseProvider.of(context);

      final viajeActivo =
          await databaseService.obtenerViajeActivoPorBascula(basculaId);
      if (viajeActivo == null) {
        await databaseService.crearViajePesaje(
          idCuadrilla: cuadrillaId,
          idBascula: basculaId,
          colorCinta: colorCinta ?? 'sin color',
          lote: 'sin lote',
          observacion: 'creado_desde_modulo_pesaje',
        );
      }

      final viajeActualizado =
          await databaseService.obtenerViajeActivoPorBascula(basculaId);
      if (mounted) {
        setState(() {
          _activeTripId = viajeActualizado?['id_viaje'] as int?;
        });
      }

      final localId = await databaseService.insertPesaje(
        idCuadrilla: cuadrillaId,
        idOperario: operarioId,
        idBascula: basculaId,
        peso: weightKg,
        unidad: weightUnit,
        fechaHora: DateTime.now(),
        colorCinta: colorCinta,
      );

      if (mounted) {
        setState(() {
          _currentBunchSaved = true;
        });
      }
      print('✅ Pesaje guardado localmente (ID: $localId)');
      return true;
    } catch (e) {
      print('❌ Error guardando pesaje: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } finally {
      _savingInProgress = false;
    }
  }

  /// 📋 Navegar a la página de información del dispositivo
  void _showDeviceInfo(BuildContext context, conn.Connected state) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DeviceInfoPage(basculaId: _selectedBasculaId),
      ),
    );
  }

  /// ⚙️ Navegar a la página de configuración
  void _showConfiguration(BuildContext context, conn.Connected state) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ConfigurationPage(),
      ),
    ).then((_) {
      if (!mounted) return;
      _lastDeviceMacSearched = null;
      unawaited(_loadCatalogs());
      final currentState = context.read<conn.ConnectionBloc>().state;
      if (currentState is conn.Connected) {
        unawaited(_autoSelectBasculaByMac(context, currentState));
      }
      unawaited(_loadSaveRules());
    });
  }

  void _showScanDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // No se puede cerrar tocando fuera
      builder: (context) => ScanDevicesDialog(
        onDeviceSelected: (device) => _connect(device),
      ),
    );
  }
}

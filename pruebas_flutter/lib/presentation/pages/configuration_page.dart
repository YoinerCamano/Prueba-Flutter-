import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/database_provider.dart';
import '../../data/local/database_service.dart';
import '../../domain/entities.dart';
import '../blocs/connection/connection_bloc.dart' as conn;

/// Pagina de configuracion del dispositivo.
/// Detiene el polling de peso al entrar y lo reanuda al salir.
class ConfigurationPage extends StatefulWidget {
  const ConfigurationPage({super.key});

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  // Estado de carga
  bool _isLoading = true;
  bool _isChangingUnit = false;
  bool _savingCuadrilla = false;
  bool _savingOperario = false;
  bool _savingBascula = false;
  bool _savingSaveRules = false;
  String? _pendingUnitChange;
  String? _cuadrillaError;
  String? _operarioError;
  String? _basculaError;

  // Datos
  String? _currentUnit;
  bool _autoSaveEnabled = false;
  bool _manualSaveEnabled = true;
  double _minimumSaveWeight = 1.0;
  double _unloadThreshold = 0.5;
  List<Cuadrilla> _cuadrillas = [];
  List<Operario> _operarios = [];
  List<Bascula> _basculas = [];
  int? _selectedCuadrillaId;
  bool _catalogsLoaded = false;

  // Formularios de alta
  final _cuadrillaCtrl = TextEditingController();
  final _operarioNombreCtrl = TextEditingController();
  final _basculaNombreCtrl = TextEditingController();
  final _basculaUbicacionCtrl = TextEditingController();
  final _minimumSaveWeightCtrl = TextEditingController();
  final _unloadThresholdCtrl = TextEditingController();

  // Suscripcion al BLoC
  StreamSubscription? _blocSubscription;
  Timer? _timeoutTimer;

  // Referencia al BLoC para dispose
  late final conn.ConnectionBloc _connectionBloc;
  DatabaseService? _databaseService;
  DatabaseService get _db {
    final db = _databaseService;
    if (db == null) {
      throw StateError('DatabaseService no inicializado');
    }
    return db;
  }

  @override
  void initState() {
    super.initState();

    _connectionBloc = context.read<conn.ConnectionBloc>();
    _connectionBloc.add(conn.StopPolling());

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        unawaited(_loadCurrentUnit());
      }
    });
  }

  @override
  void dispose() {
    _blocSubscription?.cancel();
    _timeoutTimer?.cancel();
    _cuadrillaCtrl.dispose();
    _operarioNombreCtrl.dispose();
    _basculaNombreCtrl.dispose();
    _basculaUbicacionCtrl.dispose();
    _minimumSaveWeightCtrl.dispose();
    _unloadThresholdCtrl.dispose();
    _connectionBloc.add(conn.StartPolling());
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inicializar DatabaseService cuando el árbol ya está montado.
    final wasNull = _databaseService == null;
    _databaseService ??= DatabaseProvider.of(context);
    if (wasNull && mounted) {
      unawaited(_loadCurrentUnit());
    }

    // Cargar catálogos solo una vez cuando el provider ya existe.
    if (!_catalogsLoaded && _databaseService != null) {
      _catalogsLoaded = true;
      _loadCatalogs();
    }
  }

  Future<void> _loadCurrentUnit() async {
    final currentState = _connectionBloc.state;
    if (currentState is conn.Connected && currentState.weightUnit != null) {
      await _savePreferredUnit(currentState.weightUnit!);
      setState(() {
        _currentUnit = currentState.weightUnit;
        _isLoading = false;
      });
      unawaited(_loadSaveRules());
      return;
    }

    _blocSubscription = _connectionBloc.stream.listen((state) {
      if (state is conn.Connected && mounted && state.weightUnit != null) {
        _timeoutTimer?.cancel();
        final shouldNotifySuccess =
            _isChangingUnit && _pendingUnitChange == state.weightUnit;
        setState(() {
          _currentUnit = state.weightUnit;
          _isLoading = false;
          _isChangingUnit = false;
          _pendingUnitChange = null;
        });
        unawaited(_savePreferredUnit(state.weightUnit!));
        if (shouldNotifySuccess) {
          _showMessage('Unidad actualizada');
        }
        unawaited(_loadSaveRules());
      }
    });

    final db = _databaseService;
    final preferredUnit = db != null ? await db.getPreferredWeightUnit() : 'kg';

    setState(() {
      _isLoading = false;
      _currentUnit = preferredUnit;
    });

    unawaited(_loadSaveRules());
  }

  Future<void> _loadSaveRules() async {
    final db = _databaseService;
    if (db == null) return;
    final autoSaveEnabled = await db.getAutoSaveEnabled();
    final manualSaveEnabled = await db.getManualSaveEnabled();
    final minimumSaveWeight = await db.getMinimumSaveWeight();
    final unloadThreshold = await db.getUnloadThreshold();

    var normalizedAuto = autoSaveEnabled;
    var normalizedManual = manualSaveEnabled;
    if (normalizedAuto == normalizedManual) {
      // Estado heredado/ambiguo: por defecto mantener manual activo.
      normalizedAuto = false;
      normalizedManual = true;
    }

    if (!mounted) return;
    setState(() {
      _autoSaveEnabled = normalizedAuto;
      _manualSaveEnabled = normalizedManual;
      _minimumSaveWeight = minimumSaveWeight;
      _unloadThreshold = unloadThreshold;
      _minimumSaveWeightCtrl.text = minimumSaveWeight.toStringAsFixed(2);
      _unloadThresholdCtrl.text = unloadThreshold.toStringAsFixed(2);
    });
  }

  Future<void> _saveSaveRules() async {
    final db = _databaseService;
    if (db == null) return;

    final minimum =
        double.tryParse(_minimumSaveWeightCtrl.text.trim().replaceAll(',', '.'));
    final unload =
        double.tryParse(_unloadThresholdCtrl.text.trim().replaceAll(',', '.'));

    if (minimum == null || unload == null) {
      _showMessage('Ingresa valores numéricos válidos', isError: true);
      return;
    }
    if (minimum <= 0) {
      _showMessage('El peso mínimo debe ser mayor a 0', isError: true);
      return;
    }
    if (unload < 0) {
      _showMessage('El umbral de descarga no puede ser negativo', isError: true);
      return;
    }
    if (unload >= minimum) {
      _showMessage(
        'El umbral de descarga debe ser menor al peso mínimo',
        isError: true,
      );
      return;
    }

    setState(() => _savingSaveRules = true);
    try {
      var normalizedAuto = _autoSaveEnabled;
      var normalizedManual = _manualSaveEnabled;
      if (normalizedAuto == normalizedManual) {
        normalizedAuto = false;
        normalizedManual = true;
      }

      await db.setAutoSaveEnabled(normalizedAuto);
      await db.setManualSaveEnabled(normalizedManual);
      await db.setMinimumSaveWeight(minimum);
      await db.setUnloadThreshold(unload);
      if (!mounted) return;
      setState(() {
        _autoSaveEnabled = normalizedAuto;
        _manualSaveEnabled = normalizedManual;
        _minimumSaveWeight = minimum;
        _unloadThreshold = unload;
      });
      _showMessage('Configuración de guardado actualizada');
    } catch (e) {
      _showMessage('Error guardando configuración: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingSaveRules = false);
    }
  }

  Future<void> _savePreferredUnit(String unit) async {
    final db = _databaseService;
    if (db == null) return;
    await db.setPreferredWeightUnit(unit);
  }

  Future<void> _loadCuadrillas() async {
    final db = _databaseService;
    if (db == null) return;
    try {
      final rows = await db.getCuadrillas();
      final list = rows.map((r) => Cuadrilla.fromMap(r)).toList()
        ..sort((a, b) => (a.nombre).compareTo(b.nombre));
      setState(() {
        _cuadrillas = list;
        if (_selectedCuadrillaId != null &&
            !_cuadrillas.any((c) => c.idCuadrilla == _selectedCuadrillaId)) {
          _selectedCuadrillaId = null;
        }
        // Autoseleccionar la primera cuadrilla para habilitar guardar operario.
        if (_selectedCuadrillaId == null && _cuadrillas.isNotEmpty) {
          _selectedCuadrillaId = _cuadrillas.first.idCuadrilla;
        }
      });
    } catch (_) {
      // ignore, se informa con snackbars en acciones de guardado
    } finally {}
  }

  Future<void> _loadOperarios() async {
    final db = _databaseService;
    if (db == null) return;
    try {
      final rows = await db.getOperarios();
      final list = rows.map((r) => Operario.fromMap(r)).toList();
      setState(() => _operarios = list);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadBasculas() async {
    final db = _databaseService;
    if (db == null) return;
    try {
      final rows = await db.getBasculas();
      final list = rows.map((r) => Bascula.fromMap(r)).toList();
      setState(() => _basculas = list);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadCatalogs() async {
    await Future.wait([
      _loadCuadrillas(),
      _loadOperarios(),
      _loadBasculas(),
    ]);
  }

  void _changeUnit(String targetUnit) {
    if (_isChangingUnit || _currentUnit == targetUnit) return;
    setState(() => _isChangingUnit = true);
    _pendingUnitChange = targetUnit;

    final changeCommand = targetUnit == 'kg'
        ? conn.ScaleCommand.setUnitKg.code
        : conn.ScaleCommand.setUnitLb.code;
    _connectionBloc.add(conn.SendCommandRequested(changeCommand));

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isChangingUnit) {
        setState(() {
          _isChangingUnit = false;
          _pendingUnitChange = null;
        });
        _showMessage('Error al cambiar unidad - timeout', isError: true);
      }
    });
  }

  Future<void> _handleSaveCuadrilla() async {
    final nombre = _cuadrillaCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _cuadrillaError = 'Ingresa una cuadrilla');
      return;
    }
    setState(() => _cuadrillaError = null);
    await _saveCuadrilla();
  }

  Future<void> _handleSaveOperario() async {
    final nombre = _operarioNombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _operarioError = 'Ingresa un operario');
      return;
    }
    if (_selectedCuadrillaId == null) {
      _showMessage('Selecciona una cuadrilla', isError: true);
      return;
    }
    setState(() => _operarioError = null);
    await _saveOperario();
  }

  Future<void> _handleSaveBascula() async {
    final nombre = _basculaNombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _basculaError = 'Ingresa una báscula');
      return;
    }
    setState(() => _basculaError = null);
    await _saveBascula();
  }

  Future<void> _confirmSendZero() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar acción'),
        content: const Text('¿Deseas restablecer la báscula a cero?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _sendZeroCommand();
    }
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar desconexión'),
        content:
            const Text('¿Deseas finalizar la conexión con la báscula actual?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.read<conn.ConnectionBloc>().add(conn.DisconnectRequested());
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _connectionBloc.add(conn.StartPolling());
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Configuración del sistema'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                _connectionBloc.add(conn.StartPolling());
                Navigator.of(context).pop();
              },
            ),
            bottom: TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: const [
                Tab(text: 'Ajustes'),
                Tab(text: 'Datos'),
              ],
            ),
          ),
          body: SafeArea(
            child: BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
              builder: (context, state) {
                if (state is! conn.Connected) {
                  return const Center(child: Text('No conectado'));
                }

                return TabBarView(
                  children: [
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _PreferenceCard(
                          title: 'Unidad de medición',
                          subtitle:
                              'Define cómo se visualizarán los pesos registrados',
                          isLoading: _isLoading || _isChangingUnit,
                          selectedUnit: (_currentUnit == 'lb') ? 'lb' : 'kg',
                          onChanged: _changeUnit,
                        ),
                        const SizedBox(height: 16),
                        _SaveBehaviorCard(
                          autoSaveEnabled: _autoSaveEnabled,
                          manualSaveEnabled: _manualSaveEnabled,
                          minimumSaveWeightCtrl: _minimumSaveWeightCtrl,
                          unloadThresholdCtrl: _unloadThresholdCtrl,
                          saving: _savingSaveRules,
                          onToggleAutoSave: (value) => setState(() {
                            _autoSaveEnabled = value;
                            if (value) {
                              _manualSaveEnabled = false;
                            } else if (!_manualSaveEnabled) {
                              _manualSaveEnabled = true;
                            }
                          }),
                          onToggleManualSave: (value) => setState(() {
                            _manualSaveEnabled = value;
                            if (value) {
                              _autoSaveEnabled = false;
                            } else if (!_autoSaveEnabled) {
                              _autoSaveEnabled = true;
                            }
                          }),
                          onSave: _saveSaveRules,
                        ),
                        const SizedBox(height: 16),
                        _OperationalDataCard(
                          cuadrillaCtrl: _cuadrillaCtrl,
                          operarioNombreCtrl: _operarioNombreCtrl,
                          cuadrillas: _cuadrillas,
                          selectedCuadrillaId: _selectedCuadrillaId,
                          basculaNombreCtrl: _basculaNombreCtrl,
                          savingCuadrilla: _savingCuadrilla,
                          savingOperario: _savingOperario,
                          savingBascula: _savingBascula,
                          cuadrillaError: _cuadrillaError,
                          operarioError: _operarioError,
                          basculaError: _basculaError,
                          onCuadrillaChanged: (_) {
                            if (_cuadrillaError != null) {
                              setState(() => _cuadrillaError = null);
                            }
                          },
                          onOperarioChanged: (_) {
                            if (_operarioError != null) {
                              setState(() => _operarioError = null);
                            }
                          },
                          onBasculaChanged: (_) {
                            if (_basculaError != null) {
                              setState(() => _basculaError = null);
                            }
                          },
                          onSaveCuadrilla: _handleSaveCuadrilla,
                          onSaveOperario: _handleSaveOperario,
                          onSaveBascula: _handleSaveBascula,
                          onSelectCuadrilla: (id) =>
                              setState(() => _selectedCuadrillaId = id),
                        ),
                        const SizedBox(height: 16),
                        _ActionCard(
                          title: 'Restablecer báscula',
                          subtitle: 'Restablece la báscula a cero.',
                          icon: Icons.scale_outlined,
                          actionLabel: 'Zero',
                          onPressed: _confirmSendZero,
                          isCritical: false,
                        ),
                        const SizedBox(height: 16),
                        _ActionCard(
                          title: 'Conexión del dispositivo',
                          subtitle:
                              'Finaliza la conexión con la báscula actual.',
                          icon: Icons.link_off,
                          actionLabel: 'Desconectar',
                          onPressed: _confirmDisconnect,
                          isCritical: true,
                        ),
                        const SizedBox(height: 16),
                        const _InfoCard(
                          text:
                              'Los cambios de unidad se aplican inmediatamente a la lectura de peso.',
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                    _CatalogList(
                      cuadrillas: _cuadrillas,
                      operarios: _operarios,
                      basculas: _basculas,
                      onEditCuadrilla: _editCuadrilla,
                      onDeleteCuadrilla: _deleteCuadrilla,
                      onEditOperario: _editOperario,
                      onDeleteOperario: _deleteOperario,
                      onEditBascula: _editBascula,
                      onDeleteBascula: _deleteBascula,
                      onReloadCatalogs: _loadCatalogs,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveCuadrilla() async {
    final nombre = _cuadrillaCtrl.text.trim();
    if (nombre.isEmpty) {
      _showMessage('Ingresa un nombre de cuadrilla', isError: true);
      return;
    }
    setState(() => _savingCuadrilla = true);
    try {
      await _db.insertCuadrilla(nombre: nombre);
      _cuadrillaCtrl.clear();
      await _loadCuadrillas();
      await _loadOperarios(); // refresca dependencias
      _showMessage('Cuadrilla agregada');
    } catch (e) {
      if (_isDuplicateError(e)) {
        _showMessage('Ya existe una cuadrilla con ese nombre', isError: true);
      } else {
        _showMessage('Error al guardar cuadrilla: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _savingCuadrilla = false);
    }
  }

  Future<void> _saveOperario() async {
    final nombre = _operarioNombreCtrl.text.trim();
    final idCuadrilla = _selectedCuadrillaId;
    if (nombre.isEmpty || idCuadrilla == null) {
      _showMessage('Completa nombre y selecciona cuadrilla', isError: true);
      return;
    }
    setState(() => _savingOperario = true);
    try {
      await _db.insertOperario(
          nombreCompleto: nombre, idCuadrilla: idCuadrilla);
      _operarioNombreCtrl.clear();
      _selectedCuadrillaId = null;
      // Si hay cuadrillas, dejar preseleccionada la primera
      if (_cuadrillas.isNotEmpty) {
        _selectedCuadrillaId = _cuadrillas.first.idCuadrilla;
      }
      await _loadOperarios();
      _showMessage('Operario agregado');
    } catch (e) {
      if (_isDuplicateError(e)) {
        _showMessage('Ya existe un operario con ese nombre', isError: true);
      } else {
        _showMessage('Error al guardar operario: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _savingOperario = false);
    }
  }

  Future<void> _saveBascula() async {
    final nombre = _basculaNombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _showMessage('Ingresa un nombre de bascula', isError: true);
      return;
    }
    final connState = _connectionBloc.state;
    String? modelo;
    String? numeroSerie;
    String? mac;
    if (connState is conn.Connected) {
      modelo = connState.scale.name.trim().isEmpty
          ? null
          : connState.scale.name.trim();
      final serial = connState.serialNumber?.trim();
      numeroSerie = serial != null && serial.isNotEmpty ? serial : null;
      mac = connState.device.id.trim().isEmpty
          ? null
          : connState.device.id.trim();
    }
    setState(() => _savingBascula = true);
    try {
      await _db.insertBascula(
        nombre: nombre,
        modelo: modelo,
        numeroSerie: numeroSerie,
        mac: mac,
        ubicacion: _basculaUbicacionCtrl.text.trim().isEmpty
            ? null
            : _basculaUbicacionCtrl.text.trim(),
      );
      _basculaNombreCtrl.clear();
      _basculaUbicacionCtrl.clear();
      await _loadBasculas();
      _showMessage('Bascula agregada');
    } catch (e) {
      if (_isDuplicateError(e)) {
        _showMessage('Ya existe una bascula con ese nombre', isError: true);
      } else {
        _showMessage('Error al guardar bascula: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _savingBascula = false);
    }
  }

  bool _isDuplicateError(Object error) {
    return error is Exception &&
        error.toString().toLowerCase().contains('duplicate');
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  void _sendZeroCommand() {
    _connectionBloc.add(conn.SendCommandRequested('{SCZERO}'));
    _showMessage('Comando Zero enviado', isError: false);
  }

  // ========== MÉTODOS DE EDICIÓN ==========
  Future<void> _editCuadrilla(Cuadrilla cuadrilla) async {
    final controller = TextEditingController(text: cuadrilla.nombre);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Cuadrilla'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;

    try {
      await _db.updateCuadrilla(
        id: cuadrilla.idCuadrilla!,
        nombre: result.trim(),
      );
      await _loadCuadrillas();
      if (mounted) {
        _showMessage('Cuadrilla actualizada');
      }
    } catch (e) {
      if (mounted) {
        _showMessage(
          e.toString().contains('duplicate')
              ? 'Ya existe una cuadrilla con ese nombre'
              : 'Error al actualizar: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _editOperario(Operario operario) async {
    final nombreController =
        TextEditingController(text: operario.nombreCompleto);
    int? selectedCuadrillaId = operario.idCuadrilla;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Editar Operario'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre Completo',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Cuadrilla',
                  border: OutlineInputBorder(),
                ),
                value: selectedCuadrillaId,
                items: _cuadrillas
                    .map((c) => DropdownMenuItem(
                          value: c.idCuadrilla,
                          child: Text(c.nombre),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() => selectedCuadrillaId = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: selectedCuadrillaId == null
                  ? null
                  : () => Navigator.pop(context, {
                        'nombre': nombreController.text,
                        'idCuadrilla': selectedCuadrillaId,
                      }),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      await _db.updateOperario(
        id: operario.idOperario!,
        nombreCompleto: result['nombre'],
        idCuadrilla: result['idCuadrilla'],
      );
      await _loadOperarios();
      if (mounted) {
        _showMessage('Operario actualizado');
      }
    } catch (e) {
      if (mounted) {
        _showMessage(
          e.toString().contains('duplicate')
              ? 'Ya existe un operario con ese nombre'
              : 'Error al actualizar: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _editBascula(Bascula bascula) async {
    final nombreCtrl = TextEditingController(text: bascula.nombre);
    final modeloCtrl = TextEditingController(text: bascula.modelo ?? '');
    final serieCtrl = TextEditingController(text: bascula.numeroSerie ?? '');
    final macCtrl = TextEditingController(text: bascula.mac ?? '');
    final ubicacionCtrl = TextEditingController(text: bascula.ubicacion ?? '');

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Báscula'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modeloCtrl,
                decoration: const InputDecoration(
                  labelText: 'Modelo (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: serieCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número de Serie (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: macCtrl,
                decoration: const InputDecoration(
                  labelText: 'MAC (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ubicacionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ubicación (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'nombre': nombreCtrl.text,
              'modelo': modeloCtrl.text,
              'serie': serieCtrl.text,
              'mac': macCtrl.text,
              'ubicacion': ubicacionCtrl.text,
            }),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == null || result['nombre']!.trim().isEmpty) return;

    try {
      await _db.updateBascula(
        id: bascula.idBascula!,
        nombre: result['nombre']!.trim(),
        modelo: result['modelo']!.trim().isEmpty ? null : result['modelo'],
        numeroSerie: result['serie']!.trim().isEmpty ? null : result['serie'],
        mac: result['mac']!.trim().isEmpty ? null : result['mac'],
        ubicacion:
            result['ubicacion']!.trim().isEmpty ? null : result['ubicacion'],
      );
      await _loadBasculas();
      if (mounted) {
        _showMessage('Báscula actualizada');
      }
    } catch (e) {
      if (mounted) {
        _showMessage(
          e.toString().contains('duplicate')
              ? 'Ya existe una báscula con ese nombre'
              : 'Error al actualizar: $e',
          isError: true,
        );
      }
    }
  }

  // ========== MÉTODOS DE ELIMINACIÓN ==========
  Future<void> _deleteCuadrilla(Cuadrilla cuadrilla) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Cuadrilla'),
        content:
            Text('¿Estás seguro de que deseas eliminar "${cuadrilla.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _db.deleteCuadrilla(id: cuadrilla.idCuadrilla!);
      await _loadCuadrillas();
      if (mounted) {
        _showMessage('Cuadrilla eliminada');
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Error al eliminar: $e', isError: true);
      }
    }
  }

  Future<void> _deleteOperario(Operario operario) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Operario'),
        content: Text(
            '¿Estás seguro de que deseas eliminar "${operario.nombreCompleto}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _db.deleteOperario(id: operario.idOperario!);
      await _loadOperarios();
      if (mounted) {
        _showMessage('Operario eliminado');
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Error al eliminar: $e', isError: true);
      }
    }
  }

  Future<void> _deleteBascula(Bascula bascula) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Báscula'),
        content:
            Text('¿Estás seguro de que deseas eliminar "${bascula.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _db.deleteBascula(id: bascula.idBascula!);
      await _loadBasculas();
      if (mounted) {
        _showMessage('Báscula eliminada');
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Error al eliminar: $e', isError: true);
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;

  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isLoading;
  final String selectedUnit;
  final ValueChanged<String> onChanged;

  const _PreferenceCard({
    required this.title,
    required this.subtitle,
    required this.isLoading,
    required this.selectedUnit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _SectionHeader(
                    title: title,
                    subtitle: subtitle,
                    icon: Icons.tune,
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(value: 'kg', label: Text('kg')),
                ButtonSegment<String>(value: 'lb', label: Text('lb')),
              ],
              selected: {selectedUnit},
              showSelectedIcon: false,
              onSelectionChanged: isLoading
                  ? null
                  : (selection) {
                      if (selection.isNotEmpty) {
                        onChanged(selection.first);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveBehaviorCard extends StatelessWidget {
  final bool autoSaveEnabled;
  final bool manualSaveEnabled;
  final TextEditingController minimumSaveWeightCtrl;
  final TextEditingController unloadThresholdCtrl;
  final bool saving;
  final ValueChanged<bool> onToggleAutoSave;
  final ValueChanged<bool> onToggleManualSave;
  final VoidCallback onSave;

  const _SaveBehaviorCard({
    required this.autoSaveEnabled,
    required this.manualSaveEnabled,
    required this.minimumSaveWeightCtrl,
    required this.unloadThresholdCtrl,
    required this.saving,
    required this.onToggleAutoSave,
    required this.onToggleManualSave,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              title: 'Guardado de pesaje',
              subtitle: 'Configura auto guardado, manual y umbrales de ciclo',
              icon: Icons.save_as_outlined,
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              value: autoSaveEnabled,
              onChanged: onToggleAutoSave,
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto guardado'),
            ),
            SwitchListTile.adaptive(
              value: manualSaveEnabled,
              onChanged: onToggleManualSave,
              contentPadding: EdgeInsets.zero,
              title: const Text('Guardado manual'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 210,
                  child: TextField(
                    controller: minimumSaveWeightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Peso mínimo para guardar',
                      suffixText: 'kg/lb',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: TextField(
                    controller: unloadThresholdCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Umbral de descarga',
                      suffixText: 'kg/lb',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: saving ? null : onSave,
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar configuración'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OperationalDataCard extends StatelessWidget {
  final TextEditingController cuadrillaCtrl;
  final TextEditingController operarioNombreCtrl;
  final List<Cuadrilla> cuadrillas;
  final int? selectedCuadrillaId;
  final TextEditingController basculaNombreCtrl;
  final bool savingCuadrilla;
  final bool savingOperario;
  final bool savingBascula;
  final String? cuadrillaError;
  final String? operarioError;
  final String? basculaError;
  final ValueChanged<String> onCuadrillaChanged;
  final ValueChanged<String> onOperarioChanged;
  final ValueChanged<String> onBasculaChanged;
  final VoidCallback onSaveCuadrilla;
  final VoidCallback onSaveOperario;
  final VoidCallback onSaveBascula;
  final ValueChanged<int?> onSelectCuadrilla;

  const _OperationalDataCard({
    required this.cuadrillaCtrl,
    required this.operarioNombreCtrl,
    required this.cuadrillas,
    required this.selectedCuadrillaId,
    required this.basculaNombreCtrl,
    required this.savingCuadrilla,
    required this.savingOperario,
    required this.savingBascula,
    required this.cuadrillaError,
    required this.operarioError,
    required this.basculaError,
    required this.onCuadrillaChanged,
    required this.onOperarioChanged,
    required this.onBasculaChanged,
    required this.onSaveCuadrilla,
    required this.onSaveOperario,
    required this.onSaveBascula,
    required this.onSelectCuadrilla,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              title: 'Datos operativos',
              subtitle: 'Registra datos base para operar en campo',
              icon: Icons.inventory_2_outlined,
            ),
            const SizedBox(height: 16),
            _buildFieldBlock(
              context,
              title: 'Cuadrilla',
              child: TextField(
                controller: cuadrillaCtrl,
                onChanged: onCuadrillaChanged,
                decoration: InputDecoration(
                  hintText: 'Nombre de cuadrilla',
                  border: const OutlineInputBorder(),
                  errorText: cuadrillaError,
                  isDense: true,
                ),
              ),
              saving: savingCuadrilla,
              onSave: onSaveCuadrilla,
            ),
            const SizedBox(height: 16),
            _buildFieldBlock(
              context,
              title: 'Operario',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: operarioNombreCtrl,
                      onChanged: onOperarioChanged,
                      decoration: InputDecoration(
                        hintText: 'Nombre completo',
                        border: const OutlineInputBorder(),
                        errorText: operarioError,
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Cuadrilla',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      initialValue: selectedCuadrillaId,
                      items: cuadrillas
                          .map((c) => DropdownMenuItem<int>(
                                value: c.idCuadrilla,
                                child: Text(c.nombre),
                              ))
                          .toList(),
                      onChanged: cuadrillas.isEmpty
                          ? null
                          : (id) => onSelectCuadrilla(id),
                    ),
                  ),
                ],
              ),
              saving: savingOperario,
              onSave: onSaveOperario,
            ),
            const SizedBox(height: 16),
            _buildFieldBlock(
              context,
              title: 'Báscula',
              child: TextField(
                controller: basculaNombreCtrl,
                onChanged: onBasculaChanged,
                decoration: InputDecoration(
                  hintText: 'Nombre de báscula',
                  border: const OutlineInputBorder(),
                  errorText: basculaError,
                  isDense: true,
                ),
              ),
              saving: savingBascula,
              onSave: onSaveBascula,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldBlock(
    BuildContext context, {
    required String title,
    required Widget child,
    required bool saving,
    required VoidCallback onSave,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        child,
        const SizedBox(height: 8),
        Row(
          children: [
            const Spacer(),
            FilledButton.tonal(
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onPressed;
  final bool isCritical;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actionLabel,
    required this.onPressed,
    required this.isCritical,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: isCritical
          ? colorScheme.errorContainer
          : colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: title,
              subtitle: subtitle,
              icon: icon,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: isCritical
                  ? FilledButton(
                      onPressed: onPressed,
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                      ),
                      child: Text(actionLabel),
                    )
                  : OutlinedButton.icon(
                      onPressed: onPressed,
                      icon: Icon(icon),
                      label: Text(actionLabel),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;

  const _InfoCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: colorScheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogList extends StatelessWidget {
  final List<Cuadrilla> cuadrillas;
  final List<Operario> operarios;
  final List<Bascula> basculas;
  final Function(Cuadrilla) onEditCuadrilla;
  final Function(Cuadrilla) onDeleteCuadrilla;
  final Function(Operario) onEditOperario;
  final Function(Operario) onDeleteOperario;
  final Function(Bascula) onEditBascula;
  final Function(Bascula) onDeleteBascula;
  final VoidCallback onReloadCatalogs;

  const _CatalogList({
    required this.cuadrillas,
    required this.operarios,
    required this.basculas,
    required this.onEditCuadrilla,
    required this.onDeleteCuadrilla,
    required this.onEditOperario,
    required this.onDeleteOperario,
    required this.onEditBascula,
    required this.onDeleteBascula,
    required this.onReloadCatalogs,
  });

  @override
  Widget build(BuildContext context) {
    final cuadrillaMap = {
      for (final c in cuadrillas)
        if (c.idCuadrilla != null) c.idCuadrilla!: c.nombre
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSection(
            context,
            title: 'Cuadrillas',
            icon: Icons.group,
            child: cuadrillas.isEmpty
                ? const Text('No hay cuadrillas guardadas')
                : Column(
                    children: cuadrillas
                        .map((c) => ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              leading:
                                  const Icon(Icons.group_outlined, size: 20),
                              title: Text(c.nombre),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18),
                                    onPressed: () => onEditCuadrilla(c),
                                    tooltip: 'Editar',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        size: 18, color: Colors.red),
                                    onPressed: () => onDeleteCuadrilla(c),
                                    tooltip: 'Eliminar',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 12),
          _buildSection(
            context,
            title: 'Operarios',
            icon: Icons.badge,
            child: operarios.isEmpty
                ? const Text('No hay operarios guardados')
                : Column(
                    children: operarios
                        .map((o) => ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              leading:
                                  const Icon(Icons.person_outline, size: 20),
                              title: Text(
                                '${o.nombreCompleto} - ${cuadrillaMap[o.idCuadrilla] ?? 'Sin cuadrilla'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18),
                                    onPressed: () => onEditOperario(o),
                                    tooltip: 'Editar',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        size: 18, color: Colors.red),
                                    onPressed: () => onDeleteOperario(o),
                                    tooltip: 'Eliminar',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 12),
          _buildSection(
            context,
            title: 'Basculas',
            icon: Icons.scale,
            child: basculas.isEmpty
                ? const Text('No hay basculas guardadas')
                : Column(
                    children: basculas
                        .map((b) => ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              leading:
                                  const Icon(Icons.scale_outlined, size: 20),
                              title: Text(b.nombre),
                              subtitle: Text(
                                _buildBasculaSubtitle(b),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18),
                                    onPressed: () => onEditBascula(b),
                                    tooltip: 'Editar',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        size: 18, color: Colors.red),
                                    onPressed: () => onDeleteBascula(b),
                                    tooltip: 'Eliminar',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context,
      {required String title, required IconData icon, required Widget child}) {
    final surface = Theme.of(context).colorScheme.surfaceContainer;
    return Card(
      elevation: 0,
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  String _buildBasculaSubtitle(Bascula b) {
    final parts = <String>[];
    if (b.modelo != null && b.modelo!.isNotEmpty)
      parts.add('Modelo: ${b.modelo}');
    if (b.numeroSerie != null && b.numeroSerie!.isNotEmpty) {
      parts.add('Serie: ${b.numeroSerie}');
    }
    if (b.mac != null && b.mac!.isNotEmpty) parts.add('MAC: ${b.mac}');
    if (b.ubicacion != null && b.ubicacion!.isNotEmpty) {
      parts.add('Ubicacion: ${b.ubicacion}');
    }
    return parts.isEmpty ? 'Sin datos adicionales' : parts.join(' • ');
  }
}

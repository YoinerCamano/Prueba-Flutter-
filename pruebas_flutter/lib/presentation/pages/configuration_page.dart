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

  // Datos
  String? _currentUnit;
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
        _loadCurrentUnit();
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
    _connectionBloc.add(conn.StartPolling());
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inicializar DatabaseService cuando el árbol ya está montado.
    _databaseService ??= DatabaseProvider.of(context);

    // Cargar catálogos solo una vez cuando el provider ya existe.
    if (!_catalogsLoaded && _databaseService != null) {
      _catalogsLoaded = true;
      _loadCatalogs();
    }
  }

  void _loadCurrentUnit() {
    final currentState = _connectionBloc.state;
    if (currentState is conn.Connected && currentState.weightUnit != null) {
      setState(() {
        _currentUnit = currentState.weightUnit;
        _isLoading = false;
      });
      return;
    }

    _blocSubscription = _connectionBloc.stream.listen((state) {
      if (state is conn.Connected && mounted && state.weightUnit != null) {
        _timeoutTimer?.cancel();
        setState(() {
          _currentUnit = state.weightUnit;
          _isLoading = false;
          _isChangingUnit = false;
        });
      }
    });

    setState(() {
      _isLoading = false;
      _currentUnit = 'kg';
    });
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
    setState(() => _isChangingUnit = true);

    final changeCommand = targetUnit == 'kg' ? '{SPWU0}' : '{SPWU1}';
    _connectionBloc.add(conn.SendCommandRequested(changeCommand));

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isChangingUnit) {
        setState(() => _isChangingUnit = false);
        _showMessage('Error al cambiar unidad - timeout', isError: true);
      }
    });
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
            title: const Text('Configuracion'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                _connectionBloc.add(conn.StartPolling());
                Navigator.of(context).pop();
              },
            ),
            bottom: const TabBar(
              tabs: [
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
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Unidad de peso
                          Card(
                            elevation: 0,
                            color:
                                Theme.of(context).colorScheme.surfaceContainer,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.scale,
                                          size: 24, color: Colors.blue),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Unidad de Peso',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      if (_isLoading || _isChangingUnit) ...[
                                        const Spacer(),
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  // Unidad actual
                                  if (_currentUnit != null) ...[
                                    Center(
                                      child: Column(
                                        children: [
                                          const Text(
                                            'Unidad Actual',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _currentUnit == 'kg'
                                                  ? Colors.blue.shade100
                                                  : _currentUnit == 'lb'
                                                      ? Colors.green.shade100
                                                      : Colors.grey.shade200,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: _currentUnit == 'kg'
                                                    ? Colors.blue
                                                    : _currentUnit == 'lb'
                                                        ? Colors.green
                                                        : Colors.grey,
                                                width: 2,
                                              ),
                                            ),
                                            child: Text(
                                              _currentUnit == 'kg'
                                                  ? 'Kilogramos (kg)'
                                                  : _currentUnit == 'lb'
                                                      ? 'Libras (lb)'
                                                      : 'Desconocida',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: _currentUnit == 'kg'
                                                    ? Colors.blue.shade900
                                                    : _currentUnit == 'lb'
                                                        ? Colors.green.shade900
                                                        : Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                  ],

                                  if (_currentUnit != null &&
                                      _currentUnit != 'desconocida') ...[
                                    const Text(
                                      'Cambiar a:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: _currentUnit == 'kg' ||
                                                    _isChangingUnit
                                                ? null
                                                : () => _changeUnit('kg'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blue,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 16),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            icon: const Icon(Icons.straighten),
                                            label: const Text(
                                              'Kilogramos',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: _currentUnit == 'lb' ||
                                                    _isChangingUnit
                                                ? null
                                                : () => _changeUnit('lb'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 16),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            icon: const Icon(
                                                Icons.fitness_center),
                                            label: const Text(
                                              'Libras',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],

                                  if (_isLoading && _currentUnit == null) ...[
                                    const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(20),
                                        child: Column(
                                          children: [
                                            CircularProgressIndicator(),
                                            SizedBox(height: 16),
                                            Text('Consultando unidad...'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Altas de catalogo
                          _CatalogForms(
                            cuadrillaCtrl: _cuadrillaCtrl,
                            operarioNombreCtrl: _operarioNombreCtrl,
                            cuadrillas: _cuadrillas,
                            selectedCuadrillaId: _selectedCuadrillaId,
                            basculaNombreCtrl: _basculaNombreCtrl,
                            basculaUbicacionCtrl: _basculaUbicacionCtrl,
                            savingCuadrilla: _savingCuadrilla,
                            savingOperario: _savingOperario,
                            savingBascula: _savingBascula,
                            onSaveCuadrilla: _saveCuadrilla,
                            onSaveOperario: _saveOperario,
                            onSaveBascula: _saveBascula,
                            onSelectCuadrilla: (id) =>
                                setState(() => _selectedCuadrillaId = id),
                          ),

                          const SizedBox(height: 16),

                          // Restablecer bascula a cero
                          Card(
                            elevation: 0,
                            color:
                                Theme.of(context).colorScheme.surfaceContainer,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.exposure_zero,
                                          size: 24, color: Colors.blue),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Restablecer a Cero',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Pone la bascula en cero para comenzar nuevas mediciones',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.grey,
                                        ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.tonalIcon(
                                      onPressed: () => _sendZeroCommand(),
                                      icon: const Icon(Icons.exposure_zero),
                                      label: const Text('ENVIAR COMANDO ZERO'),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Desconectar dispositivo
                          Card(
                            elevation: 0,
                            color: Colors.red.shade50,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.link_off,
                                          size: 24, color: Colors.red.shade700),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Desconectar Dispositivo',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                                color: Colors.red.shade900),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: () {
                                      context
                                          .read<conn.ConnectionBloc>()
                                          .add(conn.DisconnectRequested());
                                      Navigator.of(context).pop();
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: const Icon(Icons.link_off),
                                    label: const Text(
                                      'Desconectar',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Info
                          Card(
                            elevation: 0,
                            color: Colors.blue.shade50,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.blue),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'El cambio de unidad se aplica inmediatamente en la bascula.',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
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

class _CatalogForms extends StatelessWidget {
  final TextEditingController cuadrillaCtrl;
  final TextEditingController operarioNombreCtrl;
  final List<Cuadrilla> cuadrillas;
  final int? selectedCuadrillaId;
  final TextEditingController basculaNombreCtrl;
  final TextEditingController basculaUbicacionCtrl;
  final bool savingCuadrilla;
  final bool savingOperario;
  final bool savingBascula;
  final VoidCallback onSaveCuadrilla;
  final VoidCallback onSaveOperario;
  final VoidCallback onSaveBascula;
  final ValueChanged<int?> onSelectCuadrilla;

  const _CatalogForms({
    required this.cuadrillaCtrl,
    required this.operarioNombreCtrl,
    required this.cuadrillas,
    required this.selectedCuadrillaId,
    required this.basculaNombreCtrl,
    required this.basculaUbicacionCtrl,
    required this.savingCuadrilla,
    required this.savingOperario,
    required this.savingBascula,
    required this.onSaveCuadrilla,
    required this.onSaveOperario,
    required this.onSaveBascula,
    required this.onSelectCuadrilla,
  });

  @override
  Widget build(BuildContext context) {
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
                const Icon(Icons.add_business, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Altas rapidas',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Cuadrilla', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: cuadrillaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de cuadrilla',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: savingCuadrilla ? null : onSaveCuadrilla,
                  child: savingCuadrilla
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Operario', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: operarioNombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Cuadrilla',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    initialValue: selectedCuadrillaId,
                    items: cuadrillas
                        .map((c) => DropdownMenuItem(
                              value: c.idCuadrilla,
                              child: Text(c.nombre),
                            ))
                        .toList(),
                    onChanged: cuadrillas.isEmpty ? null : onSelectCuadrilla,
                    hint: const Text('Selecciona una cuadrilla'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: savingOperario ||
                          cuadrillas.isEmpty ||
                          selectedCuadrillaId == null
                      ? null
                      : onSaveOperario,
                  child: savingOperario
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Bascula', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              runSpacing: 8,
              spacing: 8,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: basculaNombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: basculaUbicacionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ubicacion (opcional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: savingBascula ? null : onSaveBascula,
                  icon: savingBascula
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Guardar bascula'),
                ),
              ],
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

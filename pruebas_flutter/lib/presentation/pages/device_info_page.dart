import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../blocs/device_info/device_info_bloc.dart';
import '../../data/local/database_service.dart';

/// 📋 Página dedicada para mostrar información técnica del dispositivo
/// El polling de peso se detiene automáticamente al entrar aquí
class DeviceInfoPage extends StatefulWidget {
  final int? basculaId;
  const DeviceInfoPage({super.key, this.basculaId});

  @override
  State<DeviceInfoPage> createState() => _DeviceInfoPageState();
}

class _DeviceInfoPageState extends State<DeviceInfoPage> {
  // 📊 Estados de carga
  bool _isLoading = true;
  int _currentStep = 0;
  String _currentCommand = '';

  // 📋 Datos recopilados
  String? _firmwareVersion;
  String? _cellLoadmVV;
  String? _microvoltsPerDivision;
  String? _adcNoise;
  double? _batteryVolts;
  double? _batteryPercent;

  // 🔄 Suscripción al BLoC
  StreamSubscription? _blocSubscription;
  Timer? _timeoutTimer;
  Timer? _refreshTimer; // Refresco periódico de datos técnicos
  bool _refreshInFlight = false; // Evitar solapamiento de comandos

  // 🎯 Referencias a BLoCs
  late final conn.ConnectionBloc
      _connectionBloc; // solo para pausar/reanudar peso
  late final DeviceInfoBloc _deviceInfoBloc;
  final DatabaseService _dbService = DatabaseService();

  // 📝 Secuencia de comandos (se genera dinámicamente según capacidades)
  List<Map<String, String>> _commandSequence = [];
  List<String> _periodicCommands = []; // Comandos para refresco periódico

  /// 🔧 Generar secuencia de comandos según capacidades de la báscula
  void _generateCommandSequence() {
    final connState = _connectionBloc.state;
    if (connState is! conn.Connected) {
      print('⚠️ No conectado, usando secuencia completa por defecto');
      _commandSequence = [
        {'command': '{TTCSER}', 'label': 'Número de Serie'},
        {'command': '{VA}', 'label': 'Firmware'},
        {'command': '{SCLS}', 'label': 'Celda de Carga'},
        {'command': '{SCMV}', 'label': 'Microvoltios/División'},
        {'command': '{BV}', 'label': 'Voltaje Batería'},
        {'command': '{BC}', 'label': 'Porcentaje Batería'},
      ];
      _periodicCommands = [
        '{SCLS}',
        '{SCMV}'
      ]; // Solo actualizar estos periódicamente
      return;
    }

    final scale = connState.scale;
    print('🔧 Generando secuencia de comandos para: ${scale.name}');
    print('   - Batería: ${scale.capabilities.supportsBattery}');
    print('   - Info Técnica: ${scale.capabilities.supportsTechnicalInfo}');

    _commandSequence = [];
    _periodicCommands = [];

    // Comandos de información técnica
    if (scale.capabilities.supportsTechnicalInfo) {
      // Consulta única: Número de serie y Firmware
      _commandSequence.addAll([
        {'command': '{TTCSER}', 'label': 'Número de Serie'},
        {'command': '{VA}', 'label': 'Firmware'},
      ]);

      // Consulta periódica: Celda de Carga y Microvoltios
      _commandSequence.addAll([
        {'command': '{SCLS}', 'label': 'Celda de Carga'},
        {'command': '{SCMV}', 'label': 'Microvoltios/División'},
      ]);

      _periodicCommands = ['{SCLS}', '{SCMV}'];
    }

    // Comandos de batería (solo si está soportado)
    if (scale.capabilities.supportsBattery) {
      _commandSequence.addAll([
        {'command': '{BV}', 'label': 'Voltaje Batería'},
        {'command': '{BC}', 'label': 'Porcentaje Batería'},
      ]);
    }

    print('✅ Secuencia generada con ${_commandSequence.length} comandos');
  }

  @override
  void initState() {
    super.initState();
    print('🚀 DeviceInfoPage - Iniciando...');

    // Guardar referencias a blocs
    _connectionBloc = context.read<conn.ConnectionBloc>();
    _deviceInfoBloc = context.read<DeviceInfoBloc>();

    // 🔧 Generar secuencia de comandos según capacidades
    _generateCommandSequence();

    //  DETENER POLLING DE PESO (se gestiona en ConnectionBloc)
    print('🛑 Deteniendo polling de peso...');
    _connectionBloc.add(conn.StopPolling());

    // ▶️ Iniciar escucha de datos técnicos
    _deviceInfoBloc.add(const DeviceInfoStartListening());

    // 🚫 NO iniciar refresco periódico aún - esperar a que termine la carga inicial
    // _startPeriodicRefresh();

    // Iniciar carga después de un pequeño delay
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        print('⏰ Timer de inicio: llamando a _startSequentialLoad()');
        _startSequentialLoad();
      }
    });
  }

  @override
  void dispose() {
    _blocSubscription?.cancel();
    _timeoutTimer?.cancel();
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshInFlight = false;
    // 🔄 Reanudar polling al salir
    print('🔄 DeviceInfoPage dispose - Reanudando polling...');
    _connectionBloc.add(conn.StartPolling());
    _deviceInfoBloc.add(const DeviceInfoStopListening());
    super.dispose();
  }

  /// 🔄 Iniciar carga secuencial de datos
  void _startSequentialLoad() {
    // 📊 PRIMERO: Verificar si ya hay datos en el estado actual
    final currentState = _deviceInfoBloc.state;
    print('📊 Estado actual verificado:');
    print('  - Firmware: ${currentState.firmwareVersion}');
    print('  - Cell Code: ${currentState.cellCode}');
    print('  - Cell Load: ${currentState.cellLoadmVV}');

    // Si ya hay datos, usarlos
    if (currentState.firmwareVersion != null) {
      _firmwareVersion = currentState.firmwareVersion;
    }
    if (currentState.cellLoadmVV != null) {
      _cellLoadmVV = currentState.cellLoadmVV;
      _microvoltsPerDivision = currentState.microvoltsPerDivision;
    }
    if (currentState.adcNoise != null) {
      _adcNoise = currentState.adcNoise;
    }
    if (currentState.batteryVoltage?.volts != null) {
      _batteryVolts = currentState.batteryVoltage!.volts;
    }
    if (currentState.batteryPercent?.percent != null) {
      _batteryPercent = currentState.batteryPercent!.percent;
    }

    print('🔍 Verificación de datos completos:');
    print('  - firmwareVersion: $_firmwareVersion');
    print('  - cellLoadmVV: $_cellLoadmVV');
    print('  - adcNoise: $_adcNoise');
    print('  - batteryVolts: $_batteryVolts');
    print('  - batteryPercent: $_batteryPercent');

    // Solo requerimos los datos periódicos para considerarlo completo
    if (_cellLoadmVV != null && _microvoltsPerDivision != null) {
      print('✅ Datos periódicos disponibles - Omitiendo recarga inicial');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    print('⚙️ Faltan datos, iniciando secuencia de carga...');

    // Escuchar cambios en el estado del BLoC
    _blocSubscription = _deviceInfoBloc.stream.listen((state) {
      if (mounted) {
        _processStateUpdate(state);
      }
    });

    // Enviar primer comando
    _sendNextCommand();
  }

  /// 📤 Enviar el siguiente comando en la secuencia
  void _sendNextCommand() {
    print(
        '🔍 _sendNextCommand llamado: step=$_currentStep, total=${_commandSequence.length}');

    if (_currentStep >= _commandSequence.length) {
      // ✅ Secuencia completada
      print('✅ Secuencia de comandos completada');
      setState(() {
        _isLoading = false;
      });

      // 🔄 Ahora sí iniciar refresco periódico después de que termine la carga
      print('🔄 Iniciando refresco periódico después de carga inicial');
      _startPeriodicRefresh();

      return;
    }

    final commandInfo = _commandSequence[_currentStep];
    _currentCommand = commandInfo['command']!;
    final label = commandInfo['label']!;

    print(
        '📤 [$_currentStep/${_commandSequence.length}] Enviando $_currentCommand ($label)...');

    setState(() {
      _isLoading = true;
    });

    // Enviar comando usando la referencia guardada
    _deviceInfoBloc.add(DeviceInfoSendCommandRequested(_currentCommand));

    // Configurar timeout (5 segundos por comando - aumentado para mayor confiabilidad)
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _isLoading) {
        print('⏰ TIMEOUT esperando respuesta de $_currentCommand');
        _moveToNextCommand();
      }
    });
  }

  /// 🔍 Procesar actualización del estado del BLoC
  void _processStateUpdate(DeviceInfoState state) {
    bool shouldMoveNext = false;
    bool stateChanged = false;

    // Si estamos en la carga inicial, procesar comando específico
    if (_isLoading && _currentCommand.isNotEmpty) {
      switch (_currentCommand) {
        case '{TTCSER}':
          if (state.serialNumber != null &&
              state.serialNumber != 'No disponible') {
            print('📋 Recibido: Serial = ${state.serialNumber}');
            _saveSerialNumberToDatabase(state.serialNumber!);
            shouldMoveNext = true;
            stateChanged = true;
          }
          break;

        case '{BV}':
          if (state.batteryVoltage?.volts != null &&
              state.batteryVoltage!.volts != _batteryVolts) {
            print('🔋 Recibido: Voltaje = ${state.batteryVoltage!.volts} V');
            _batteryVolts = state.batteryVoltage!.volts;
            shouldMoveNext = true;
            stateChanged = true;
          }
          break;

        case '{BC}':
          if (state.batteryPercent?.percent != null &&
              state.batteryPercent!.percent != _batteryPercent) {
            print(
                '🔋 Recibido: Porcentaje = ${state.batteryPercent!.percent} %');
            _batteryPercent = state.batteryPercent!.percent;
            shouldMoveNext = true;
            stateChanged = true;
          }
          break;

        case '{VA}':
          if (state.firmwareVersion != null &&
              state.firmwareVersion != _firmwareVersion) {
            print('🔧 Recibido: Firmware = ${state.firmwareVersion}');
            _firmwareVersion = state.firmwareVersion;
            shouldMoveNext = true;
            stateChanged = true;
          }
          break;

        case '{SCLS}':
          if (state.cellLoadmVV != null && state.cellLoadmVV != _cellLoadmVV) {
            print(
                '⚡ Recibido SCLS: state.cellLoadmVV = ${state.cellLoadmVV}, antes era $_cellLoadmVV');
            _cellLoadmVV = state.cellLoadmVV;
            shouldMoveNext = true;
            stateChanged = true;
          } else if (state.cellLoadmVV == null) {
            print('⚠️ SCLS: state.cellLoadmVV es nulo');
          } else if (state.cellLoadmVV == _cellLoadmVV) {
            print(
                '⚠️ SCLS: sin cambios (${state.cellLoadmVV} == $_cellLoadmVV)');
          }
          break;

        case '{SCMV}':
          if (state.microvoltsPerDivision != null &&
              state.microvoltsPerDivision != _microvoltsPerDivision) {
            print(
                '🎚️ Recibido SCMV: state.microvoltsPerDivision = ${state.microvoltsPerDivision}, antes era $_microvoltsPerDivision');
            _microvoltsPerDivision = state.microvoltsPerDivision;
            shouldMoveNext = true;
            stateChanged = true;
          } else if (state.microvoltsPerDivision == null) {
            print('⚠️ SCMV: state.microvoltsPerDivision es nulo');
          } else if (state.microvoltsPerDivision == _microvoltsPerDivision) {
            print(
                '⚠️ SCMV: sin cambios (${state.microvoltsPerDivision} == $_microvoltsPerDivision)');
          }
          break;

        case '{SCAV}':
          if (state.adcNoise != null && state.adcNoise != _adcNoise) {
            print('📡 Recibido: Ruido CAD = ${state.adcNoise}');
            _adcNoise = state.adcNoise;
            shouldMoveNext = true;
            stateChanged = true;
          }
          break;
      }
    } else {
      // Fuera de la carga inicial: actualizar SIEMPRE que cambien los valores
      // (refresco periódico o actualizaciones automáticas)
      if (state.cellLoadmVV != null && state.cellLoadmVV != _cellLoadmVV) {
        print('♻️ Actualizado: Celda = ${state.cellLoadmVV}');
        _cellLoadmVV = state.cellLoadmVV;
        stateChanged = true;
      }
      if (state.microvoltsPerDivision != null &&
          state.microvoltsPerDivision != _microvoltsPerDivision) {
        print('♻️ Actualizado: µV/div = ${state.microvoltsPerDivision}');
        _microvoltsPerDivision = state.microvoltsPerDivision;
        stateChanged = true;
      }
      if (state.adcNoise != null && state.adcNoise != _adcNoise) {
        print('♻️ Actualizado: Ruido CAD = ${state.adcNoise}');
        _adcNoise = state.adcNoise;
        stateChanged = true;
      }
      // Guardar ruido CAD localmente
      _adcNoise = state.adcNoise ?? _adcNoise;
      if (state.batteryVoltage?.volts != null &&
          state.batteryVoltage!.volts != _batteryVolts) {
        print('♻️ Actualizado: Voltaje = ${state.batteryVoltage!.volts}');
        _batteryVolts = state.batteryVoltage!.volts;
        stateChanged = true;
      }
      if (state.batteryPercent?.percent != null &&
          state.batteryPercent!.percent != _batteryPercent) {
        print('♻️ Actualizado: Porcentaje = ${state.batteryPercent!.percent}');
        _batteryPercent = state.batteryPercent!.percent;
        stateChanged = true;
      }
    }

    if (shouldMoveNext) {
      _moveToNextCommand();
    }

    // Actualizar UI si hubo cambios
    if (stateChanged && mounted) {
      setState(() {});
    }
  }

  /// ➡️ Avanzar al siguiente comando
  void _moveToNextCommand() {
    _timeoutTimer?.cancel();
    _currentStep++;

    // Delay prudente para comandos técnicos (80ms) para evitar cruce de información
    // Es diferente al peso que es prioritario y se envía más rápidamente
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) {
        _sendNextCommand();
      }
    });
  }

  /// ♻️ Refresco periódico mientras la página está abierta
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    // Solo refrescar comandos periódicos (celda y microvoltios)
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isLoading || _refreshInFlight) return;
      _refreshInFlight = true;

      final cmds = _periodicCommands;
      print('🔄 Refresco periódico: ${cmds.length} comandos');
      print('🔄 Comandos: ${cmds.join(", ")}');

      const gap = Duration(milliseconds: 80);
      for (var i = 0; i < cmds.length; i++) {
        Future.delayed(gap * i, () {
          if (!mounted) return;
          final cmd = cmds[i];
          print('♻️ Refresco técnico secuencial: enviando $cmd');
          _deviceInfoBloc.add(DeviceInfoSendCommandRequested(cmd));
        });
      }

      // Liberar la bandera después de enviar la secuencia completa
      Future.delayed(gap * cmds.length + const Duration(milliseconds: 50), () {
        if (mounted) {
          _refreshInFlight = false;
        }
      });
    });
  }

  /// 💾 Guardar número de serie en la base de datos
  Future<void> _saveSerialNumberToDatabase(String serialNumber) async {
    try {
      final connState = _connectionBloc.state;
      if (connState is! conn.Connected) {
        print('⚠️ No hay conexión activa, no se puede guardar serial');
        return;
      }

      final mac = connState.device.id;
      print(
          '💾 Guardando número de serie "$serialNumber" para MAC: $mac (Báscula ID: ${widget.basculaId})');

      if (widget.basculaId == null) {
        print('⚠️ ID de báscula no disponible');
        return;
      }

      // Buscar la báscula por MAC en la BD
      final bascula = await _dbService.getBasculaByMac(mac);
      if (bascula == null) {
        print('⚠️ Báscula con MAC $mac no encontrada en BD');
        return;
      }

      // Actualizar la báscula con el nuevo número de serie
      await _dbService.updateBascula(
        id: bascula.idBascula!,
        nombre: bascula.nombre,
        modelo: bascula.modelo,
        numeroSerie: serialNumber,
        mac: bascula.mac,
        ubicacion: bascula.ubicacion,
      );

      print('✅ Número de serie guardado exitosamente en BD');
    } catch (e) {
      print('❌ Error al guardar número de serie: $e');
    }
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
          title: const Text('Información del Dispositivo'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // Reanudar polling antes de salir
              print('🔄 Botón back - Reanudando polling...');
              _connectionBloc.add(conn.StartPolling());
              Navigator.of(context).pop();
            },
          ),
        ),
        body: SafeArea(
          child: BlocBuilder<DeviceInfoBloc, DeviceInfoState>(
            builder: (context, state) {
              final connState = context.watch<conn.ConnectionBloc>().state;
              if (connState is! conn.Connected) {
                return const Center(child: Text('No conectado'));
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 📱 Información básica del dispositivo
                    Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceContainer,
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
                                const Icon(Icons.bluetooth_connected,
                                    size: 24, color: Colors.blue),
                                const SizedBox(width: 8),
                                Text(
                                  'Dispositivo Conectado',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildBasicInfoRow(
                              icon: Icons.devices,
                              label: 'Nombre',
                              value: connState.device.name,
                            ),
                            const SizedBox(height: 12),
                            _buildBasicInfoRow(
                              icon: Icons.fingerprint,
                              label: 'ID/MAC',
                              value: connState.device.id,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 🔧 Información técnica - Siempre mostrar
                    _buildTechnicalInfoCard(state, connState),
                    const SizedBox(height: 16),

                    // 🔋 Información de batería (solo si el modelo lo soporta)
                    if (connState.scale.capabilities.supportsBattery)
                      _buildBatteryInfoCard(state),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 🔧 Tarjeta de información técnica
  Widget _buildTechnicalInfoCard(
      DeviceInfoState state, conn.Connected connState) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 24, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Información Técnica',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_isLoading) ...[
                  const Spacer(),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _buildTechInfoRow(
              icon: Icons.memory,
              label: 'Firmware',
              value: state.firmwareVersion ??
                  _firmwareVersion ??
                  (_isLoading ? 'Cargando...' : 'No disponible'),
            ),
            const SizedBox(height: 12),
            _buildTechInfoRow(
              icon: Icons.tag,
              label: 'Número de Serie',
              value: state.serialNumber ?? 'No disponible',
            ),
            const SizedBox(height: 12),
            _buildTechInfoRow(
              icon: Icons.electrical_services,
              label: 'Celda de Carga (mV/V)',
              value: state.cellLoadmVV ??
                  (_isLoading ? 'Cargando...' : 'No disponible'),
            ),
            const SizedBox(height: 12),
            _buildTechInfoRow(
              icon: Icons.tune,
              label: 'Microvoltios/División',
              value: state.microvoltsPerDivision ??
                  (_isLoading ? 'Cargando...' : 'No disponible'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.grey,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildTechInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: TextStyle(
              color: value != 'No disponible' ? Colors.green : Colors.grey,
              fontWeight: FontWeight.w500,
              fontFamily: value != 'No disponible' ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBatteryInfoCard(DeviceInfoState state) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.battery_std, size: 24, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Batería',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_isLoading) ...[
                  const Spacer(),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _buildTechInfoRow(
              icon: Icons.battery_charging_full,
              label: 'Voltaje',
              value: _formatVolts(state.batteryVoltage?.volts ?? _batteryVolts),
            ),
            const SizedBox(height: 12),
            _buildTechInfoRow(
              icon: Icons.battery_full,
              label: 'Porcentaje',
              value: _formatPercent(
                  state.batteryPercent?.percent ?? _batteryPercent),
            ),
          ],
        ),
      ),
    );
  }

  String _formatVolts(double? volts) {
    if (volts == null) return _isLoading ? 'Cargando...' : 'No disponible';
    return '${volts.toStringAsFixed(2)} V';
  }

  String _formatPercent(double? percent) {
    if (percent == null) return _isLoading ? 'Cargando...' : 'No disponible';
    return '${percent.toStringAsFixed(0)} %';
  }
}

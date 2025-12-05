import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/connection/connection_bloc.dart' as conn;
import '../blocs/device_info/device_info_bloc.dart';

/// 📋 Página dedicada para mostrar información técnica del dispositivo
/// El polling de peso se detiene automáticamente al entrar aquí
class DeviceInfoPage extends StatefulWidget {
  const DeviceInfoPage({super.key});

  @override
  State<DeviceInfoPage> createState() => _DeviceInfoPageState();
}

class _DeviceInfoPageState extends State<DeviceInfoPage> {
  // 📊 Estados de carga
  bool _isLoading = true;
  int _currentStep = 0;
  String _currentCommand = '';

  // 📋 Datos recopilados
  String? _serialNumber;
  String? _firmwareVersion;
  String? _cellCode;
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

  // 📝 Secuencia de comandos
  final List<Map<String, String>> _commandSequence = [
    {'command': '{TTCSER}', 'label': 'Número de Serie'},
    {'command': '{VA}', 'label': 'Firmware'},
    {'command': '{SACC}', 'label': 'Código de Celda'},
    {'command': '{SCLS}', 'label': 'Celda de Carga'},
    {'command': '{SCMV}', 'label': 'Microvoltios/División'},
    {'command': '{SCAV}', 'label': 'Ruido CAD'},
    {'command': '{BV}', 'label': 'Voltaje Batería'},
    {'command': '{BC}', 'label': 'Porcentaje Batería'},
  ];

  @override
  void initState() {
    super.initState();
    print('🚀 DeviceInfoPage - Iniciando...');

    // Guardar referencias a blocs
    _connectionBloc = context.read<conn.ConnectionBloc>();
    _deviceInfoBloc = context.read<DeviceInfoBloc>();

    // 🛑 DETENER POLLING DE PESO (se gestiona en ConnectionBloc)
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
    print('  - Serial: ${currentState.serialNumber}');
    print('  - Firmware: ${currentState.firmwareVersion}');
    print('  - Cell Code: ${currentState.cellCode}');
    print('  - Cell Load: ${currentState.cellLoadmVV}');

    // Si ya hay datos, usarlos
    if (currentState.serialNumber != null) {
      _serialNumber = currentState.serialNumber;
    }
    if (currentState.firmwareVersion != null) {
      _firmwareVersion = currentState.firmwareVersion;
    }
    if (currentState.cellCode != null) {
      _cellCode = currentState.cellCode;
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
    print('  - serialNumber: $_serialNumber');
    print('  - firmwareVersion: $_firmwareVersion');
    print('  - cellCode: $_cellCode');
    print('  - cellLoadmVV: $_cellLoadmVV');
    print('  - adcNoise: $_adcNoise');
    print('  - batteryVolts: $_batteryVolts');
    print('  - batteryPercent: $_batteryPercent');

    // Si todos los datos están disponibles, no recargar
    if (_serialNumber != null &&
        _firmwareVersion != null &&
        _cellCode != null &&
        _cellLoadmVV != null &&
        _adcNoise != null &&
        _batteryVolts != null &&
        _batteryPercent != null) {
      print('✅ Todos los datos ya disponibles - Omitiendo recarga');
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
              state.serialNumber != _serialNumber) {
            print('📋 Recibido: Número de Serie = ${state.serialNumber}');
            _serialNumber = state.serialNumber;
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

        case '{SACC}':
          if (state.cellCode != null && state.cellCode != _cellCode) {
            print('🏷️ Recibido: Código de Celda = ${state.cellCode}');
            _cellCode = state.cellCode;
            shouldMoveNext = true;
            stateChanged = true;
          }
          break;

        case '{SCLS}':
          if (state.cellLoadmVV != null && state.cellLoadmVV != _cellLoadmVV) {
            print('⚡ Recibido: Celda = ${state.cellLoadmVV}');
            _cellLoadmVV = state.cellLoadmVV;
            shouldMoveNext = true;
            stateChanged = true;
          }
          break;

        case '{SCMV}':
          if (state.microvoltsPerDivision != null &&
              state.microvoltsPerDivision != _microvoltsPerDivision) {
            print('🎚️ Recibido: µV/div = ${state.microvoltsPerDivision}');
            _microvoltsPerDivision = state.microvoltsPerDivision;
            shouldMoveNext = true;
            stateChanged = true;
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
    // Temporal: refrescar el paquete completo de datos técnicos en secuencia
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isLoading || _refreshInFlight) return;
      _refreshInFlight = true;

      final cmds = _commandSequence.map((e) => e['command']!).toList();
      print('🔄 Refresco periódico: ${cmds.length} comandos en total');
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

                    // 🔋 Información de batería al final
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
              icon: Icons.confirmation_number,
              label: 'Número de Serie',
              value: state.serialNumber ??
                  _serialNumber ??
                  (_isLoading ? 'Cargando...' : 'No disponible'),
            ),
            const SizedBox(height: 12),
            _buildTechInfoRow(
              icon: Icons.memory,
              label: 'Firmware',
              value: state.firmwareVersion ??
                  _firmwareVersion ??
                  (_isLoading ? 'Cargando...' : 'No disponible'),
            ),
            const SizedBox(height: 12),
            _buildTechInfoRow(
              icon: Icons.qr_code,
              label: 'Código de Celda',
              value: state.cellCode ??
                  _cellCode ??
                  (_isLoading ? 'Cargando...' : 'No disponible'),
            ),
            const SizedBox(height: 12),
            _buildTechInfoRow(
              icon: Icons.electrical_services,
              label: 'Celda de Carga (mV/V)',
              value: state.cellLoadmVV ??
                  _cellLoadmVV ??
                  (_isLoading ? 'Cargando...' : 'No disponible'),
            ),
            const SizedBox(height: 12),
            _buildTechInfoRow(
              icon: Icons.tune,
              label: 'Microvoltios/División',
              value: state.microvoltsPerDivision ??
                  _microvoltsPerDivision ??
                  (_isLoading ? 'Cargando...' : 'No disponible'),
            ),
            const SizedBox(height: 12),
            _buildTechInfoRow(
              icon: Icons.graphic_eq,
              label: 'Ruido CAD',
              value: state.adcNoise ??
                  _adcNoise ??
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

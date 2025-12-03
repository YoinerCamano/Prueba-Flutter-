import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/connection/connection_bloc.dart' as conn;

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

  // 🔄 Suscripción al BLoC
  StreamSubscription? _blocSubscription;
  Timer? _timeoutTimer;
  Timer? _refreshTimer; // Refresco periódico de datos técnicos
  bool _refreshInFlight = false; // Evitar solapamiento de comandos
  int _refreshStep = 0; // 0: SCLS (celda/microvoltios), 1: SCAV (ruido CAD)

  // 🎯 Referencia al BLoC para dispose
  late final conn.ConnectionBloc _connectionBloc;

  // 📝 Secuencia de comandos
  final List<Map<String, String>> _commandSequence = [
    {'command': '{TTCSER}', 'label': 'Número de Serie'},
    {'command': '{VA}', 'label': 'Firmware'},
    {'command': '{SACC}', 'label': 'Código de Celda'},
    {'command': '{SCLS}', 'label': 'Especificaciones'},
    {'command': '{SCAV}', 'label': 'Ruido CAD'},
  ];

  @override
  void initState() {
    super.initState();
    print('🚀 DeviceInfoPage - Iniciando...');

    // Guardar referencia al bloc
    _connectionBloc = context.read<conn.ConnectionBloc>();

    // 🛑 DETENER POLLING DE PESO
    print('🛑 Deteniendo polling de peso...');
    _connectionBloc.add(conn.StopPolling());

    // Iniciar refresco periódico de datos técnicos
    _startPeriodicRefresh();

    // Iniciar carga después de un pequeño delay
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
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
    super.dispose();
  }

  /// 🔄 Iniciar carga secuencial de datos
  void _startSequentialLoad() {
    // 📊 PRIMERO: Verificar si ya hay datos en el estado actual
    final currentState = _connectionBloc.state;
    if (currentState is conn.Connected) {
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

      // Si todos los datos están disponibles, no recargar
      if (_serialNumber != null &&
          _firmwareVersion != null &&
          _cellCode != null &&
          _cellLoadmVV != null &&
          _adcNoise != null) {
        print('✅ Todos los datos ya disponibles - Omitiendo recarga');
        setState(() {
          _isLoading = false;
        });
        return;
      }
    }

    // Escuchar cambios en el estado del BLoC
    _blocSubscription = _connectionBloc.stream.listen((state) {
      if (state is conn.Connected && mounted) {
        _processStateUpdate(state);
      }
    });

    // Enviar primer comando
    _sendNextCommand();
  }

  /// 📤 Enviar el siguiente comando en la secuencia
  void _sendNextCommand() {
    if (_currentStep >= _commandSequence.length) {
      // ✅ Secuencia completada
      print('✅ Secuencia de comandos completada');
      setState(() {
        _isLoading = false;
      });
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
    _connectionBloc.add(
      conn.SendCommandRequested(_currentCommand),
    );

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
  void _processStateUpdate(conn.Connected state) {
    bool shouldMoveNext = false;
    bool stateChanged = false;

    // Verificar qué dato llegó según el comando actual
    switch (_currentCommand) {
      case '{TTCSER}':
        if (state.serialNumber != null && state.serialNumber != _serialNumber) {
          print('📋 Recibido: Número de Serie = ${state.serialNumber}');
          _serialNumber = state.serialNumber;
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
          print(
              '⚡ Recibido: Especificaciones = ${state.cellLoadmVV}, ${state.microvoltsPerDivision}');
          _cellLoadmVV = state.cellLoadmVV;
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

      default:
        // Durante el refresco periódico (_currentCommand está vacío o es diferente)
        // Actualizar siempre los valores técnicos si cambian
        if (state.cellLoadmVV != null && state.cellLoadmVV != _cellLoadmVV) {
          print(
              '♻️ Actualizado: Celda = ${state.cellLoadmVV}, µV/div = ${state.microvoltsPerDivision}');
          _cellLoadmVV = state.cellLoadmVV;
          _microvoltsPerDivision = state.microvoltsPerDivision;
          stateChanged = true;
        }
        if (state.adcNoise != null && state.adcNoise != _adcNoise) {
          print('♻️ Actualizado: Ruido CAD = ${state.adcNoise}');
          _adcNoise = state.adcNoise;
          stateChanged = true;
        }
        break;
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

    // Delay más largo antes del siguiente comando (500ms para dar tiempo al dispositivo)
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _sendNextCommand();
      }
    });
  }

  /// ♻️ Refresco periódico mientras la página está abierta
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    // Refrescar cada 500ms alternando SCLS y SCAV para máxima velocidad
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || _isLoading || _refreshInFlight) return;
      _refreshInFlight = true;

      // Alternar entre comandos para no saturar el dispositivo
      final cmd = (_refreshStep % 2 == 0) ? '{SCLS}' : '{SCAV}';
      _refreshStep++;

      print('♻️ Refresco técnico: enviando $cmd');
      _connectionBloc.add(conn.SendCommandRequested(cmd));

      // Liberar bandera después de un breve tiempo para permitir próximo ciclo
      Future.delayed(const Duration(milliseconds: 200), () {
        _refreshInFlight = false;
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
          child: BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
            builder: (context, state) {
              if (state is! conn.Connected) {
                return const Center(
                  child: Text('No conectado'),
                );
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
                              value: state.device.name,
                            ),
                            const SizedBox(height: 12),
                            _buildBasicInfoRow(
                              icon: Icons.fingerprint,
                              label: 'ID/MAC',
                              value: state.device.id,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 🔧 Información técnica - Siempre mostrar
                    _buildTechnicalInfoCard(state),
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
  Widget _buildTechnicalInfoCard(conn.Connected state) {
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
}

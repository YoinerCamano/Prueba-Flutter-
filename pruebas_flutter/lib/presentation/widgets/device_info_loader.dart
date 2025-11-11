import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/connection/connection_bloc.dart' as conn;

/// 🔄 Widget que carga la información del dispositivo de forma secuencial
/// Solicita cada comando y espera su respuesta antes de continuar
class DeviceInfoLoader extends StatefulWidget {
  const DeviceInfoLoader({super.key});

  @override
  State<DeviceInfoLoader> createState() => _DeviceInfoLoaderState();
}

class _DeviceInfoLoaderState extends State<DeviceInfoLoader> {
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

  // 🔄 Suscripción al BLoC
  StreamSubscription? _blocSubscription;
  Timer? _timeoutTimer;

  // 📝 Secuencia de comandos
  final List<Map<String, String>> _commandSequence = [
    {'command': '{TTCSER}', 'label': 'Número de Serie'},
    {'command': '{VA}', 'label': 'Firmware'},
    {'command': '{SACC}', 'label': 'Código de Celda'},
    {'command': '{SCLS}', 'label': 'Especificaciones'},
  ];

  @override
  void initState() {
    super.initState();
    print('🚀 DeviceInfoLoader - Iniciando carga secuencial...');

    // 🛑 DETENER POLLING DE PESO para evitar interferencias
    print('🛑 Deteniendo polling de peso...');
    context.read<conn.ConnectionBloc>().add(conn.StopPolling());

    _startSequentialLoad();
  }

  @override
  void dispose() {
    _blocSubscription?.cancel();
    _timeoutTimer?.cancel();

    // 🔄 REANUDAR POLLING DE PESO al salir
    print('🔄 Reanudando polling de peso...');
    context.read<conn.ConnectionBloc>().add(conn.StartPolling());

    super.dispose();
  }

  /// 🔄 Iniciar carga secuencial de datos
  void _startSequentialLoad() {
    final bloc = context.read<conn.ConnectionBloc>();

    // Escuchar cambios en el estado del BLoC
    _blocSubscription = bloc.stream.listen((state) {
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
      print('🔄 Reanudando polling de peso después de completar...');

      // Reanudar polling de peso
      context.read<conn.ConnectionBloc>().add(conn.StartPolling());

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

    // Enviar comando
    context.read<conn.ConnectionBloc>().add(
          conn.SendCommandRequested(_currentCommand),
        );

    // Configurar timeout (3 segundos por comando)
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isLoading) {
        print('⏰ TIMEOUT esperando respuesta de $_currentCommand');
        _moveToNextCommand();
      }
    });
  }

  /// 🔍 Procesar actualización del estado del BLoC
  void _processStateUpdate(conn.Connected state) {
    bool shouldMoveNext = false;

    // Verificar qué dato llegó según el comando actual
    switch (_currentCommand) {
      case '{TTCSER}':
        if (state.serialNumber != null && state.serialNumber != _serialNumber) {
          print('📋 Recibido: Número de Serie = ${state.serialNumber}');
          _serialNumber = state.serialNumber;
          shouldMoveNext = true;
        }
        break;

      case '{VA}':
        if (state.firmwareVersion != null &&
            state.firmwareVersion != _firmwareVersion) {
          print('🔧 Recibido: Firmware = ${state.firmwareVersion}');
          _firmwareVersion = state.firmwareVersion;
          shouldMoveNext = true;
        }
        break;

      case '{SACC}':
        if (state.cellCode != null && state.cellCode != _cellCode) {
          print('🏷️ Recibido: Código de Celda = ${state.cellCode}');
          _cellCode = state.cellCode;
          shouldMoveNext = true;
        }
        break;

      case '{SCLS}':
        if (state.cellLoadmVV != null && state.cellLoadmVV != _cellLoadmVV) {
          print(
              '⚡ Recibido: Especificaciones = ${state.cellLoadmVV}, ${state.microvoltsPerDivision}');
          _cellLoadmVV = state.cellLoadmVV;
          _microvoltsPerDivision = state.microvoltsPerDivision;
          shouldMoveNext = true;
        }
        break;
    }

    if (shouldMoveNext) {
      _moveToNextCommand();
    }
  }

  /// ➡️ Avanzar al siguiente comando
  void _moveToNextCommand() {
    _timeoutTimer?.cancel();
    _currentStep++;

    // Pequeño delay antes del siguiente comando
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _sendNextCommand();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // 🔄 Mostrar indicador de carga
      return Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Obteniendo información del dispositivo...',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${_currentStep + 1} de ${_commandSequence.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              if (_currentCommand.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _currentCommand,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.blue,
                        fontFamily: 'monospace',
                      ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // ✅ Mostrar información completa
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.info_outline, size: 24, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Información Técnica',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Datos
            _buildInfoRow(
              icon: Icons.confirmation_number,
              label: 'Número de Serie',
              value: _serialNumber ?? 'No disponible',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.memory,
              label: 'Firmware',
              value: _firmwareVersion ?? 'No disponible',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.qr_code,
              label: 'Código de Celda',
              value: _cellCode ?? 'No disponible',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.electrical_services,
              label: 'Celda de Carga',
              value: _cellLoadmVV ?? 'No disponible',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.tune,
              label: 'μV/División',
              value: _microvoltsPerDivision ?? 'No disponible',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
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

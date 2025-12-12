import 'dart:async';
import 'package:flutter/material.dart';
import '../blocs/connection/connection_bloc.dart' as conn;

/// 🔧 Widget especializado para mostrar información técnica del dispositivo
/// Envía comandos específicos para obtener datos como SN, firmware, etc.
class DeviceInfoWidget extends StatefulWidget {
  final conn.ConnectionBloc connectionBloc;

  const DeviceInfoWidget({
    super.key,
    required this.connectionBloc,
  });

  @override
  State<DeviceInfoWidget> createState() => _DeviceInfoWidgetState();
}

class _DeviceInfoWidgetState extends State<DeviceInfoWidget> {
  // 📋 Datos técnicos del dispositivo
  String? firmwareVersion;
  String? cellCode;
  String? cellLoadmVV;
  String? microvoltsPerDivision;

  // 🔄 Estados de carga
  bool isLoadingFirmware = false;
  bool isLoadingCellCode = false;
  bool isLoadingCellSpecs = false;

  // 📡 Timeout para comandos
  Timer? _commandTimeout;
  StreamSubscription? _responseSubscription;

  @override
  void initState() {
    super.initState();
    _startLoadingDeviceInfo();
  }

  @override
  void dispose() {
    _commandTimeout?.cancel();
    _responseSubscription?.cancel();
    super.dispose();
  }

  /// 🚀 Iniciar carga de información del dispositivo
  void _startLoadingDeviceInfo() {
    print('🔧 === INICIANDO CARGA DE INFORMACIÓN DEL DISPOSITIVO ===');

    // Escuchar respuestas del ConnectionBloc
    _responseSubscription = widget.connectionBloc.stream.listen((state) {
      if (state is conn.Connected) {
        // Aquí procesaremos las respuestas de los comandos específicos
        // Por ahora simularemos datos
        _processDeviceResponse(state);
      }
    });

    // Secuencia de comandos para obtener información
    _requestFirmwareVersion();
  }

  /// 📤 Solicitar versión de firmware {VA}
  void _requestFirmwareVersion() {
    setState(() => isLoadingFirmware = true);
    print('📤 Solicitando versión de firmware: {VA}');

    widget.connectionBloc.add(conn.SendCommandRequested('{VA}'));

    _commandTimeout?.cancel();
    _commandTimeout = Timer(const Duration(seconds: 3), () {
      if (mounted && isLoadingFirmware) {
        setState(() {
          isLoadingFirmware = false;
          firmwareVersion = 'Timeout - No disponible';
        });
        _requestCellCode();
      }
    });
  }

  /// 📤 Solicitar código de celda {SACC}
  void _requestCellCode() {
    setState(() => isLoadingCellCode = true);
    print('📤 Solicitando código de celda: {SACC}');

    widget.connectionBloc.add(conn.SendCommandRequested('{SACC}'));

    _commandTimeout?.cancel();
    _commandTimeout = Timer(const Duration(seconds: 3), () {
      if (mounted && isLoadingCellCode) {
        setState(() {
          isLoadingCellCode = false;
          cellCode = 'Timeout - No disponible';
        });
        _requestCellSpecs();
      }
    });
  }

  /// 📤 Solicitar especificaciones de celda {SCLS}
  void _requestCellSpecs() {
    setState(() => isLoadingCellSpecs = true);
    print('📤 Solicitando especificaciones de celda: {SCLS}');

    widget.connectionBloc.add(conn.SendCommandRequested('{SCLS}'));

    _commandTimeout?.cancel();
    _commandTimeout = Timer(const Duration(seconds: 3), () {
      if (mounted && isLoadingCellSpecs) {
        setState(() {
          isLoadingCellSpecs = false;
          cellLoadmVV = 'Timeout - No disponible';
          microvoltsPerDivision = 'Timeout - No disponible';
        });
      }
    });
  }

  /// 🔍 Procesar respuestas del dispositivo
  void _processDeviceResponse(conn.Connected state) {
    // Por ahora simulamos las respuestas
    // En una implementación real, aquí analizaríamos las respuestas específicas
    // de cada comando basándonos en el patrón de respuesta del dispositivo

    // Simular datos por ahora (esto se reemplazará con lógica real)
    if (isLoadingFirmware && firmwareVersion == null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            firmwareVersion = 'v2.3.1'; // Simulado
            isLoadingFirmware = false;
          });
          _requestCellCode();
        }
      });
    }

    if (isLoadingCellCode && cellCode == null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            cellCode = 'S3-LOAD-001'; // Simulado
            isLoadingCellCode = false;
          });
          _requestCellSpecs();
        }
      });
    }

    if (isLoadingCellSpecs && cellLoadmVV == null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            cellLoadmVV = '2.0 mV/V'; // Simulado
            // Requisito: microvoltsPerDivision SIN unidad, solo valor numérico.
            microvoltsPerDivision = '0.1'; // Simulado (sin "μV/div")
            isLoadingCellSpecs = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🔢 Número de Serie
        _buildTechnicalInfoRow(
          icon: Icons.memory,
          label: 'Firmware',
          value: firmwareVersion,
          isLoading: isLoadingFirmware,
          command: '{VA}',
        ),
        const SizedBox(height: 12),

        // 🏷️ Código de Celda
        _buildTechnicalInfoRow(
          icon: Icons.qr_code,
          label: 'Código de Celda',
          value: cellCode,
          isLoading: isLoadingCellCode,
          command: '{SACC}',
        ),
        const SizedBox(height: 12),

        // ⚡ Celda de Carga mV/V
        _buildTechnicalInfoRow(
          icon: Icons.electrical_services,
          label: 'Celda de Carga',
          value: cellLoadmVV,
          isLoading: isLoadingCellSpecs,
          command: '{SCLS}',
        ),
        const SizedBox(height: 12),

        // 📏 Microvoltios/División
        _buildTechnicalInfoRow(
          icon: Icons.tune,
          label: 'μV/División',
          value: microvoltsPerDivision,
          isLoading: isLoadingCellSpecs,
          command: '{SCLS}',
        ),
      ],
    );
  }

  /// 📋 Construir fila de información técnica
  Widget _buildTechnicalInfoRow({
    required IconData icon,
    required String label,
    String? value,
    bool isLoading = false,
    String? command,
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
          child: isLoading
              ? Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      command ?? 'Cargando...',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                )
              : Text(
                  value ?? 'No disponible',
                  style: TextStyle(
                    color: value != null ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w500,
                    fontFamily: value != null ? 'monospace' : null,
                  ),
                ),
        ),
      ],
    );
  }
}

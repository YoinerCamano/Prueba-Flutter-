import 'package:flutter/material.dart';

/// 🔧 Tarjeta de información técnica del dispositivo
/// Muestra datos como SN, firmware, código de celda, etc.
/// Similar a WeightCard pero para información técnica
class DeviceInfoCard extends StatelessWidget {
  final String? firmwareVersion;
  final String? cellCode;
  final String? cellLoadmVV;
  final String? microvoltsPerDivision;

  const DeviceInfoCard({
    super.key,
    this.firmwareVersion,
    this.cellCode,
    this.cellLoadmVV,
    this.microvoltsPerDivision,
  });

  /// Verificar si toda la información está disponible
  bool get isFullyLoaded =>
      firmwareVersion != null &&
      cellCode != null &&
      cellLoadmVV != null &&
      microvoltsPerDivision != null;

  /// Verificar si está cargando (NO tiene toda la información todavía)
  bool get isLoading => !isFullyLoaded;

  @override
  Widget build(BuildContext context) {
    // 🔍 Log para depuración
    print(
        '🔧 DeviceInfoCard - FW: $firmwareVersion, Cell: $cellCode, mVV: $cellLoadmVV, μV: $microvoltsPerDivision');

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
                const Icon(Icons.info_outline, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Información del Dispositivo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (!isFullyLoaded && isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Siempre mostrar los campos (cargando o con datos)
            _buildInfoRow(
              context,
              icon: Icons.memory,
              label: 'Firmware',
              value: firmwareVersion,
              command: '{VA}',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              context,
              icon: Icons.qr_code,
              label: 'Código de Celda',
              value: cellCode,
              command: '{SACC}',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              context,
              icon: Icons.electrical_services,
              label: 'Celda de Carga',
              value: cellLoadmVV,
              command: '{SCLS}',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              context,
              icon: Icons.tune,
              label: 'μV/División',
              value: microvoltsPerDivision,
              command: '{SCLS}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? value,
    String? command,
  }) {
    final isLoading = value == null && command != null;

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
                      command,
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

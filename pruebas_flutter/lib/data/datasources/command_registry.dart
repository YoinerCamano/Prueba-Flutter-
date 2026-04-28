import '../../domain/entities/device_command.dart';
import '../models/pending_command.dart';

class CommandRegistry {
  // Diccionario de comandos conocidos
  final Map<String, DeviceCommand> _knownCommands = {
    '{RW}': const DeviceCommand(
      code: '{RW}',
      key: 'peso',
      description: 'Lectura de peso',
    ),
    '{BC}': const DeviceCommand(
      code: '{BC}',
      key: 'bateria_porcentaje',
      description: 'Nivel de batería (%)',
    ),
    '{BV}': const DeviceCommand(
      code: '{BV}',
      key: 'bateria_voltaje',
      description: 'Voltaje de batería',
    ),
    '{VA}': const DeviceCommand(
      code: '{VA}',
      key: 'version_firmware',
      description: 'Versión de firmware',
    ),
    '{SACC}': const DeviceCommand(
      code: '{SACC}',
      key: 'codigo_celda',
      description: 'Código de celda',
    ),
    '{SCLS}': const DeviceCommand(
      code: '{SCLS}',
      key: 'especificaciones_celda',
      description: 'Especificaciones de celda',
    ),
    '{SCMV}': const DeviceCommand(
      code: '{SCMV}',
      key: 'microvoltios_division',
      description: 'Microvoltios/División',
    ),
    '{SCZERO}': const DeviceCommand(
      code: '{SCZERO}',
      key: 'reset_zero',
      description: 'Resetear báscula a cero',
    ),
    '{SCAV}': const DeviceCommand(
      code: '{SCAV}',
      key: 'ruido_cad',
      description: 'Ruido CAD (conversor A/D)',
    ),
    '{MSWU}': const DeviceCommand(
      code: '{MSWU}',
      key: 'unidad_peso',
      description: 'Consultar unidad de peso',
    ),
    '{MSWU0}': const DeviceCommand(
      code: '{MSWU0}',
      key: 'cambiar_unidad_kg',
      description: 'Cambiar unidad a kilogramos',
    ),
    '{MSWU1}': const DeviceCommand(
      code: '{MSWU1}',
      key: 'cambiar_unidad_lb',
      description: 'Cambiar unidad a libras',
    ),
    '{ZA1}': const DeviceCommand(
      code: '{ZA1}',
      key: 'habilitar_ack',
      description: 'Habilitar confirmación de comandos',
      timeout: Duration(milliseconds: 2000),
    ),
    '{ZE1}': const DeviceCommand(
      code: '{ZE1}',
      key: 'consultar_errores',
      description: 'Obtener errores de la báscula',
    ),
    '{ZC1}': const DeviceCommand(
      code: '{ZC1}',
      key: 'retorno_carro',
      description: 'Configurar retorno de carro',
    ),
  };

  // Lista de comandos enviados que están "pendientes" de respuesta
  final List<PendingCommand> _pending = [];

  /// Llamas esto justo ANTES de enviar por Bluetooth
  PendingCommand registerOutgoing(String code) {
    final cmd = _knownCommands[code];
    final pending = PendingCommand(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      rawCommand: code,
      mappedCommand: cmd,
      createdAt: DateTime.now(),
    );
    _pending.add(pending);
    print('📝 REGISTRADO: $pending');
    return pending;
  }

  /// Llamas esto cuando recibes algo desde la báscula
  /// Aquí decides con qué comando lo relacionas
  PendingCommand? resolveWithIncoming(String incomingData) {
    // Primero limpia timeouts automáticamente
    purgeTimeouts();

    // estrategia 1: tomar el último comando enviado
    if (_pending.isEmpty) return null;

    // Importante: No aplicar heurísticas que descarten datos entre corchetes,
    // ya que muchas respuestas de info también vienen formateadas como "[valor]".

    final last = _pending.last;
    last.responseData = incomingData;
    last.resolvedAt = DateTime.now();

    // lo quitas de la lista de pendientes
    _pending.remove(last);

    final latency = last.resolvedAt!.difference(last.createdAt).inMilliseconds;
    print('🔗 RESUELTO: ${last.rawCommand} → "$incomingData" (${latency}ms)');

    return last;
  }

  DeviceCommand? getCommandInfo(String code) => _knownCommands[code];

  List<PendingCommand> get pendingCommands => List.unmodifiable(_pending);

  /// Limpia comandos viejos que nunca respondieron
  void purgeTimeouts() {
    final now = DateTime.now();
    final toRemove = _pending.where((p) {
      // Timeout más conservador: 1 segundo por defecto
      final timeout =
          p.mappedCommand?.timeout ?? const Duration(milliseconds: 1000);
      return now.difference(p.createdAt) > timeout;
    }).toList();

    for (final expired in toRemove) {
      _pending.remove(expired);
      print(
          '⏰ TIMEOUT: ${expired.rawCommand} (${expired.mappedCommand?.key ?? 'desconocido'})');
    }
  }

  /// Obtiene estadísticas de comandos
  Map<String, int> getStats() {
    final stats = <String, int>{};
    for (final cmd in _knownCommands.values) {
      stats[cmd.key] = 0;
    }
    return stats;
  }
}

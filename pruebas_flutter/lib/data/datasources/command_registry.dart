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
    '{TTCSER}': const DeviceCommand(
      code: '{TTCSER}',
      key: 'numero_serie',
      description: 'Número de serie',
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

    // Heurística: evitar resolver lecturas de peso/ruido como si fueran
    // respuestas a comandos de información del dispositivo.
    // Patrón de peso: "[U?-?99.9]" (con o sin U, signo y decimales)
    final weightLike = RegExp(r"\[(U?-?\d+\.?\d*\s*)\]");
    final trimmed = incomingData.trim();

    // Revisar el último comando pendiente sin removerlo aún
    final lastPending = _pending.last;
    final isInfoCommand = lastPending.rawCommand == '{TTCSER}' ||
        lastPending.rawCommand == '{VA}' ||
        lastPending.rawCommand == '{SACC}' ||
        lastPending.rawCommand == '{SCLS}' ||
        lastPending.rawCommand == '{SCAV}';

    // Si estamos esperando info y llegó algo con forma de peso, NO resolver.
    if (isInfoCommand && weightLike.hasMatch(trimmed)) {
      // Mantener el comando como pendiente para que llegue la respuesta real
      return null;
    }

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

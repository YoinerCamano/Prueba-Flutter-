import '../../domain/entities/device_command.dart';

class PendingCommand {
  final String id;
  final String rawCommand; // lo que mandaste: "{RW}"
  final DeviceCommand? mappedCommand;
  final DateTime createdAt;
  DateTime? resolvedAt;
  String? responseData;

  PendingCommand({
    required this.id,
    required this.rawCommand,
    required this.mappedCommand,
    required this.createdAt,
    this.resolvedAt,
    this.responseData,
  });

  @override
  String toString() =>
      'PendingCommand(id: $id, rawCommand: $rawCommand, key: ${mappedCommand?.key})';
}

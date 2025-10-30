class DeviceCommand {
  final String code; // ej. "{RW}"
  final String key; // ej. "peso"
  final String description; // ej. "Lectura de peso"
  final Duration timeout; // para saber cuánto esperar una respuesta

  const DeviceCommand({
    required this.code,
    required this.key,
    required this.description,
    this.timeout = const Duration(seconds: 3),
  });

  @override
  String toString() =>
      'DeviceCommand(code: $code, key: $key, description: $description)';
}

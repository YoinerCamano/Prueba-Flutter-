import '../../domain/entities.dart';

enum TransportType { ble, classic }

/// Capacidades declarativas para cada modelo de báscula.
class ScaleCapabilities {
  final bool supportsModelQuery;
  final bool supportsAck;
  final bool supportsUnits;
  final bool supportsZero;
  final bool supportsTare;
  final bool supportsHold;
  final bool supportsBattery;
  final bool supportsTechnicalInfo;
  final bool supportsWeight;

  const ScaleCapabilities({
    this.supportsModelQuery = true,
    this.supportsAck = true,
    this.supportsUnits = true,
    this.supportsZero = true,
    this.supportsTare = true,
    this.supportsHold = true,
    this.supportsBattery = true,
    this.supportsTechnicalInfo = true,
    this.supportsWeight = true,
  });
}

/// Descriptor de un modelo de báscula y sus capacidades.
class ScaleDescriptor {
  final String id;
  final String name;
  final TransportType transport;
  final ScaleCapabilities capabilities;
  final Map<String, String> commandOverrides;
  final List<String> aliases;

  const ScaleDescriptor({
    required this.id,
    required this.name,
    required this.transport,
    this.capabilities = const ScaleCapabilities(),
    this.commandOverrides = const {},
    this.aliases = const [],
  });

  bool supportsCommand(String command) {
    final normalized = _normalize(command);
    if (!capabilities.supportsModelQuery && normalized == '{ZN}') return false;
    if (!capabilities.supportsAck && normalized == '{ZA1}') return false;
    if (!capabilities.supportsUnits &&
        (normalized == '{MSWU}' ||
            normalized == '{MSWU0}' ||
            normalized == '{MSWU1}')) {
      return false;
    }
    if (!capabilities.supportsZero && normalized == '{SCZERO}') return false;
    if (!capabilities.supportsBattery &&
        (normalized == '{BV}' || normalized == '{BC}')) {
      return false;
    }
    if (!capabilities.supportsTechnicalInfo &&
        (normalized == '{TTCSER}' ||
            normalized == '{VA}' ||
            normalized == '{SACC}' ||
            normalized == '{SCLS}' ||
            normalized == '{SCMV}' ||
            normalized == '{SCAV}')) {
      return false;
    }
    if (!capabilities.supportsWeight && normalized == '{RW}') return false;
    return true;
  }

  String resolveCommand(String command) {
    final normalized = _normalize(command);
    return commandOverrides[normalized] ?? normalized;
  }

  static String _normalize(String raw) => raw.trim().toUpperCase();
}

/// Registro centralizado de modelos conocidos y sus capacidades.
class ScaleModelRegistry {
  static const ScaleDescriptor truTestS3 = ScaleDescriptor(
    id: 'S3',
    name: 'Tru-Test S3',
    transport: TransportType.ble,
    capabilities: ScaleCapabilities(),
    aliases: ['S3', 'TRUTEST S3', 'TRU-TEST S3', 'TRU TEST S3'],
  );

  static const ScaleDescriptor eziWeigh = ScaleDescriptor(
    id: 'EZI',
    name: 'EziWeigh 7',
    transport: TransportType.classic,
    capabilities: ScaleCapabilities(
      supportsModelQuery: false, // evita {ZN}, va directo a peso
      supportsAck: false,
      supportsUnits: false,
      supportsZero: false,
      supportsTare: false,
      supportsHold: false,
      supportsBattery: false,
      supportsTechnicalInfo: true, // solo serial en la práctica
      supportsWeight: true,
    ),
    commandOverrides: {
      // EziWeigh7 usa mismo formato que S3: {RW} con llaves
    },
    aliases: ['EZIWEIGH7', 'EZIWEIGH', 'EZIWEIGH 7', 'EZI', 'EZI WEIGH'],
  );

  static const ScaleDescriptor genericBle = ScaleDescriptor(
    id: 'BLE_GENERIC',
    name: 'Báscula BLE',
    transport: TransportType.ble,
    capabilities: ScaleCapabilities(),
    aliases: ['BLE', 'GENERIC_BLE'],
  );

  static const ScaleDescriptor genericClassic = ScaleDescriptor(
    id: 'CLASSIC_GENERIC',
    name: 'Báscula Clásica',
    transport: TransportType.classic,
    capabilities: ScaleCapabilities(
      supportsAck: false,
      supportsUnits: false,
      supportsZero: false,
      supportsTare: false,
      supportsHold: false,
    ),
    aliases: ['CLASSIC', 'SPP', 'RS232'],
  );

  static const ScaleDescriptor unknown = ScaleDescriptor(
    id: 'UNKNOWN',
    name: 'Modelo desconocido',
    transport: TransportType.ble,
    capabilities: ScaleCapabilities(),
  );

  static const String truTestS3Id = 'S3';
  static const String eziWeighId = 'EZI';
  static const String genericBleId = 'BLE_GENERIC';
  static const String genericClassicId = 'CLASSIC_GENERIC';
  static const String unknownId = 'UNKNOWN';

  final Map<String, ScaleDescriptor> _byId = const {
    ScaleModelRegistry.truTestS3Id: truTestS3,
    ScaleModelRegistry.eziWeighId: eziWeigh,
    ScaleModelRegistry.genericBleId: genericBle,
    ScaleModelRegistry.genericClassicId: genericClassic,
    ScaleModelRegistry.unknownId: unknown,
  };

  final Map<String, String> _aliasToId = const {
    'S3': ScaleModelRegistry.truTestS3Id,
    'TRUTEST S3': ScaleModelRegistry.truTestS3Id,
    'TRU-TEST S3': ScaleModelRegistry.truTestS3Id,
    'TRU TEST S3': ScaleModelRegistry.truTestS3Id,
    'EZIWEIGH': ScaleModelRegistry.eziWeighId,
    'EZIWEIGH7': ScaleModelRegistry.eziWeighId,
    'EZIWEIGH 7': ScaleModelRegistry.eziWeighId,
    'EZI WEIGH': ScaleModelRegistry.eziWeighId,
    'EZI': ScaleModelRegistry.eziWeighId,
    'BLE': ScaleModelRegistry.genericBleId,
    'GENERIC_BLE': ScaleModelRegistry.genericBleId,
    'CLASSIC': ScaleModelRegistry.genericClassicId,
    'SPP': ScaleModelRegistry.genericClassicId,
    'RS232': ScaleModelRegistry.genericClassicId,
  };

  ScaleDescriptor resolveFromModelResponse(
    String response, {
    TransportType? hintTransport,
  }) {
    final normalized =
        response.replaceAll(RegExp(r'[\[\]\s]+'), '').toUpperCase();
    // Tolerar prefijos parciales (p.ej. "EZIWEI")
    for (final entry in _aliasToId.entries) {
      if (normalized.contains(entry.key)) {
        return _byId[entry.value] ?? unknown;
      }
      // Prefijo parcial de al menos 5 chars
      if (entry.key.length >= 5 &&
          entry.key.startsWith(normalized) &&
          normalized.length >= 5) {
        return _byId[entry.value] ?? unknown;
      }
    }

    if (hintTransport == TransportType.classic) {
      return genericClassic;
    }
    if (hintTransport == TransportType.ble) {
      return genericBle;
    }
    return unknown;
  }

  ScaleDescriptor guessFromDevice(BtDevice device) {
    final id = device.id.toUpperCase();
    final name = device.name.toUpperCase();
    if (id.contains('DE:FD:76:A4:D7:ED') || name.contains('S3')) {
      return truTestS3;
    }
    if (name.contains('EZI')) {
      return eziWeigh;
    }
    if (id.contains(':')) {
      return genericClassic;
    }
    return genericBle;
  }

  TransportType chooseTransport({
    required String deviceId,
    ScaleDescriptor? descriptor,
  }) {
    if (descriptor != null) return descriptor.transport;
    return deviceId.contains(':') ? TransportType.classic : TransportType.ble;
  }

  bool isCommandSupported(ScaleDescriptor descriptor, String command) {
    return descriptor.supportsCommand(command);
  }

  String mapCommand(ScaleDescriptor descriptor, String command) {
    return descriptor.resolveCommand(command);
  }
}

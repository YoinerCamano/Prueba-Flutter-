import 'dart:async';
import '../../domain/bluetooth_repository.dart';
import 'scale_model_registry.dart';

/// Estrategia base para manejar la conexión y comunicación con una báscula
abstract class ScaleConnectionStrategy {
  final BluetoothRepository repository;
  final ScaleDescriptor descriptor;

  ScaleConnectionStrategy({
    required this.repository,
    required this.descriptor,
  });

  /// Inicializar la báscula después de conectar
  Future<void> initialize({
    required void Function(String command) sendCommand,
    required void Function(int step) startTimeout,
  });

  /// Procesar línea cruda del stream de datos
  /// Retorna null si necesita más datos (fragmentación)
  /// Retorna la línea completa cuando está lista para procesar
  String? processRawLine(String rawLine);

  /// Limpiar estado interno de la estrategia
  void reset();

  /// Verificar si el comando necesita tracking especial
  bool needsCommandTracking(String command) => false;
}

/// Estrategia para Tru-Test S3 (BLE)
class TruTestS3Strategy extends ScaleConnectionStrategy {
  TruTestS3Strategy({
    required super.repository,
    required super.descriptor,
  });

  @override
  Future<void> initialize({
    required void Function(String command) sendCommand,
    required void Function(int step) startTimeout,
  }) async {
    // S3 soporta secuencia completa: {ZN} → {ZA1} → {MSWU}
    print('🔧 S3: Secuencia de inicialización completa');
    // La inicialización se maneja en el bloc (envía {ZN} automáticamente)
  }

  @override
  String? processRawLine(String rawLine) {
    // S3 envía respuestas completas, no necesita buffer de fragmentos
    return rawLine;
  }

  @override
  void reset() {
    // S3 no tiene estado interno especial
  }

  @override
  bool needsCommandTracking(String command) {
    // S3 no necesita tracking especial, responde rápido
    return false;
  }
}

/// Estrategia para EziWeigh7 (Bluetooth Classic)
class EziWeigh7Strategy extends ScaleConnectionStrategy {
  String _fragmentBuffer = '';
  bool _insideBrackets = false;

  EziWeigh7Strategy({
    required super.repository,
    required super.descriptor,
  });

  @override
  Future<void> initialize({
    required void Function(String command) sendCommand,
    required void Function(int step) startTimeout,
  }) async {
    // EziWeigh7 no soporta {ZN}, {ZA1}, ni {MSWU}
    // Va directo a lectura de peso
    print('🔧 EziWeigh7: Sin secuencia de inicialización, directo a peso');
    // El bloc detectará que no soporta comandos init y empezará polling
  }

  @override
  String? processRawLine(String rawLine) {
    // 🔧 MANEJO DE RESPUESTAS FRAGMENTADAS
    // EziWeigh7 envía respuestas partidas: "[" + "26" + "]"

    // Caso 1: Fragmento inicial - tiene '[' pero NO tiene ']'
    if (rawLine.startsWith('[') && !rawLine.contains(']')) {
      _insideBrackets = true;
      _fragmentBuffer = rawLine;
      print('📦 EziWeigh7: Fragmento inicial "$rawLine"');
      return null; // Esperar más fragmentos
    }

    // Caso 2: Fragmento intermedio - estamos acumulando y aún no llega ']'
    if (_insideBrackets && !rawLine.contains(']')) {
      _fragmentBuffer += rawLine;
      print(
          '📦 EziWeigh7: Fragmento intermedio "$rawLine" → Buffer: "$_fragmentBuffer"');
      return null; // Esperar más fragmentos
    }

    // Caso 3: Fragmento final - estamos acumulando y llega ']'
    if (_insideBrackets && rawLine.contains(']')) {
      _fragmentBuffer += rawLine;
      final completeLine = _fragmentBuffer;
      _fragmentBuffer = '';
      _insideBrackets = false;
      print('✅ EziWeigh7: Mensaje reconstruido "$completeLine"');
      return completeLine;
    }

    // Caso 4: Mensaje completo en una línea (raro pero posible)
    print('📨 EziWeigh7: Mensaje completo "$rawLine"');
    return rawLine;
  }

  @override
  void reset() {
    _fragmentBuffer = '';
    _insideBrackets = false;
  }

  @override
  bool needsCommandTracking(String command) {
    // EziWeigh7 necesita tracking: no enviar siguiente {RW} hasta recibir respuesta completa
    return command.toUpperCase().contains('RW');
  }
}

/// Factory para crear la estrategia apropiada según el modelo
class ScaleStrategyFactory {
  static ScaleConnectionStrategy create({
    required BluetoothRepository repository,
    required ScaleDescriptor descriptor,
  }) {
    switch (descriptor.id) {
      case 'S3':
        return TruTestS3Strategy(
          repository: repository,
          descriptor: descriptor,
        );
      case 'EZI':
        return EziWeigh7Strategy(
          repository: repository,
          descriptor: descriptor,
        );
      default:
        // Fallback: usar estrategia simple (sin fragmentación)
        return TruTestS3Strategy(
          repository: repository,
          descriptor: descriptor,
        );
    }
  }
}

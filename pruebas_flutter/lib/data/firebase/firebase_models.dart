import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo de datos para una medición en Firebase
class MeasurementModel {
  final String id;
  final String deviceId;
  final double weight;
  final String unit;
  final String? sessionId;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  MeasurementModel({
    required this.id,
    required this.deviceId,
    required this.weight,
    required this.unit,
    this.sessionId,
    required this.timestamp,
    this.metadata = const {},
  });

  factory MeasurementModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MeasurementModel(
      id: doc.id,
      deviceId: data['deviceId'] ?? '',
      weight: (data['weight'] ?? 0.0).toDouble(),
      unit: data['unit'] ?? 'kg',
      sessionId: data['sessionId'],
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      metadata: data['metadata'] ?? {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'weight': weight,
      'unit': unit,
      'sessionId': sessionId,
      'timestamp': Timestamp.fromDate(timestamp),
      'metadata': metadata,
    };
  }
}

/// Modelo de datos para una sesión en Firebase
class SessionModel {
  final String id;
  final String deviceId;
  final String? animalId;
  final DateTime startTime;
  final DateTime? endTime;
  final int measurementCount;
  final Map<String, dynamic> metadata;
  final String status; // 'active', 'completed', 'cancelled'

  SessionModel({
    required this.id,
    required this.deviceId,
    this.animalId,
    required this.startTime,
    this.endTime,
    this.measurementCount = 0,
    this.metadata = const {},
    this.status = 'active',
  });

  factory SessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SessionModel(
      id: doc.id,
      deviceId: data['deviceId'] ?? '',
      animalId: data['animalId'],
      startTime: (data['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (data['endTime'] as Timestamp?)?.toDate(),
      measurementCount: data['measurementCount'] ?? 0,
      metadata: data['metadata'] ?? {},
      status: data['status'] ?? 'active',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'animalId': animalId,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,
      'measurementCount': measurementCount,
      'metadata': metadata,
      'status': status,
    };
  }

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
}

/// Modelo de datos para un dispositivo en Firebase
class DeviceModel {
  final String id;
  final String name;
  final String bondState;
  final DateTime lastSeen;

  DeviceModel({
    required this.id,
    required this.name,
    required this.bondState,
    required this.lastSeen,
  });

  factory DeviceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DeviceModel(
      id: doc.id,
      name: data['name'] ?? '',
      bondState: data['bondState'] ?? '',
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'bondState': bondState,
      'lastSeen': Timestamp.fromDate(lastSeen),
    };
  }
}

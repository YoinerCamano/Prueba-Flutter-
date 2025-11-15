import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities.dart';

/// Servicio para gestionar datos en Firebase Firestore
class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Colecciones
  static const String _devicesCollection = 'devices';
  static const String _measurementsCollection = 'measurements';
  static const String _sessionsCollection = 'sessions';

  /// Guarda información de un dispositivo
  Future<void> saveDevice(BtDevice device) async {
    try {
      await _firestore.collection(_devicesCollection).doc(device.id).set({
        'id': device.id,
        'name': device.name,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error guardando dispositivo: $e');
      rethrow;
    }
  }

  /// Guarda una medición de peso
  Future<String> saveMeasurement({
    required String deviceId,
    required double weight,
    required String unit,
    String? sessionId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      final doc = await _firestore.collection(_measurementsCollection).add({
        'deviceId': deviceId,
        'weight': weight,
        'unit': unit,
        'sessionId': sessionId,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': now,
        'metadata': metadata ?? {},
      });
      return doc.id;
    } catch (e) {
      print('Error guardando medición: $e');
      rethrow;
    }
  }

  /// Crea una nueva sesión de mediciones
  Future<String> createSession({
    required String deviceId,
    String? animalId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final doc = await _firestore.collection(_sessionsCollection).add({
        'deviceId': deviceId,
        'animalId': animalId,
        'startTime': FieldValue.serverTimestamp(),
        'endTime': null,
        'measurementCount': 0,
        'metadata': metadata ?? {},
        'status': 'active',
      });
      return doc.id;
    } catch (e) {
      print('Error creando sesión: $e');
      rethrow;
    }
  }

  /// Finaliza una sesión de mediciones
  Future<void> endSession(String sessionId) async {
    try {
      await _firestore.collection(_sessionsCollection).doc(sessionId).update({
        'endTime': FieldValue.serverTimestamp(),
        'status': 'completed',
      });
    } catch (e) {
      print('Error finalizando sesión: $e');
      rethrow;
    }
  }

  /// Obtiene las mediciones de una sesión
  Stream<List<Map<String, dynamic>>> getMeasurements({
    String? sessionId,
    String? deviceId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
  }) {
    Query query = _firestore.collection(_measurementsCollection);

    if (sessionId != null) {
      query = query.where('sessionId', isEqualTo: sessionId);
    }
    if (deviceId != null) {
      query = query.where('deviceId', isEqualTo: deviceId);
    }
    if (startDate != null) {
      query = query.where('createdAt', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('createdAt', isLessThanOrEqualTo: endDate);
    }

    return query
        // Orden primario por timestamp del servidor (cuando ya está disponible)
        .orderBy('timestamp', descending: true)
        // Orden secundario por createdAt del cliente para que aparezca inmediato
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
            .toList());
  }

  /// Obtiene el total de mediciones guardadas
  Future<int> getTotalMeasurements({
    String? sessionId,
    String? deviceId,
  }) async {
    try {
      Query query = _firestore.collection(_measurementsCollection);

      if (sessionId != null) {
        query = query.where('sessionId', isEqualTo: sessionId);
      }
      if (deviceId != null) {
        query = query.where('deviceId', isEqualTo: deviceId);
      }

      final snapshot = await query.count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      print('Error contando mediciones: $e');
      return 0;
    }
  }

  /// Obtiene las sesiones de un dispositivo
  Stream<List<Map<String, dynamic>>> getSessions({
    String? deviceId,
    String? status,
    int limit = 50,
  }) {
    Query query = _firestore.collection(_sessionsCollection);

    if (deviceId != null) {
      query = query.where('deviceId', isEqualTo: deviceId);
    }
    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }

    return query
        .orderBy('startTime', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
            .toList());
  }

  /// Obtiene todos los dispositivos guardados
  Stream<List<Map<String, dynamic>>> getDevices() {
    return _firestore
        .collection(_devicesCollection)
        .orderBy('lastSeen', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList());
  }

  /// Elimina una medición
  Future<void> deleteMeasurement(String measurementId) async {
    try {
      await _firestore
          .collection(_measurementsCollection)
          .doc(measurementId)
          .delete();
    } catch (e) {
      print('Error eliminando medición: $e');
      rethrow;
    }
  }

  /// Elimina una sesión y todas sus mediciones
  Future<void> deleteSession(String sessionId) async {
    try {
      // Eliminar todas las mediciones de la sesión
      final measurements = await _firestore
          .collection(_measurementsCollection)
          .where('sessionId', isEqualTo: sessionId)
          .get();

      final batch = _firestore.batch();
      for (var doc in measurements.docs) {
        batch.delete(doc.reference);
      }

      // Eliminar la sesión
      batch.delete(_firestore.collection(_sessionsCollection).doc(sessionId));

      await batch.commit();
    } catch (e) {
      print('Error eliminando sesión: $e');
      rethrow;
    }
  }

  /// Actualiza el contador de mediciones de una sesión
  Future<void> incrementSessionMeasurements(String sessionId) async {
    try {
      await _firestore.collection(_sessionsCollection).doc(sessionId).update({
        'measurementCount': FieldValue.increment(1),
      });
    } catch (e) {
      print('Error actualizando contador de sesión: $e');
      rethrow;
    }
  }
}

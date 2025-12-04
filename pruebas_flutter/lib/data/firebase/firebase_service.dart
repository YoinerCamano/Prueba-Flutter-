import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities.dart';

/// Servicio para gestionar datos en Firebase Firestore
class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Colecciones
  static const String _devicesCollection = 'devices';
  static const String _measurementsCollection = 'measurements';
  static const String _sessionsCollection = 'sessions';
  // Tablas de racimos (diarias) y sus entradas
  static const String _bunchTablesCollection = 'bunch_tables';
  static const String _bunchEntriesCollection = 'bunch_entries';

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

  /// Crea una tabla diaria de racimos identificada por hora de inicio del primer racimo
  Future<String> createBunchTable({
    required String deviceId,
    required DateTime startDateTime,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final doc = await _firestore.collection(_bunchTablesCollection).add({
        'deviceId': deviceId,
        'startDateTime': startDateTime.toUtc(),
        'createdAt': FieldValue.serverTimestamp(),
        'metadata': metadata ?? {},
      });
      return doc.id;
    } catch (e) {
      print('Error creando tabla de racimos: $e');
      rethrow;
    }
  }

  /// Obtiene o crea la tabla de racimos del día actual (según device)
  Future<String> getOrCreateTodayBunchTable({
    required String deviceId,
    DateTime? now,
  }) async {
    try {
      final current = now ?? DateTime.now().toUtc();
      final startOfDay = DateTime.utc(current.year, current.month, current.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final existing = await _firestore
          .collection(_bunchTablesCollection)
          .where('deviceId', isEqualTo: deviceId)
          .where('startDateTime', isGreaterThanOrEqualTo: startOfDay)
          .where('startDateTime', isLessThan: endOfDay)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        return existing.docs.first.id;
      }
      return await createBunchTable(deviceId: deviceId, startDateTime: current);
    } catch (e) {
      print('Error obteniendo/creando tabla diaria: $e');
      rethrow;
    }
  }

  /// Agrega una entrada de racimo a la tabla
  Future<String> addBunchEntry({
    required String tableId,
    required int number,
    required double weightKg,
    required DateTime weighingTime,
    String? cintaColor,
    String? cuadrilla,
    String? lote,
    bool? recusado,
  }) async {
    try {
      final doc = await _firestore.collection(_bunchEntriesCollection).add({
        'tableId': tableId,
        'number': number,
        'weightKg': weightKg,
        'weighingTime': weighingTime.toUtc(),
        'cintaColor': cintaColor,
        'cuadrilla': cuadrilla,
        'lote': lote,
        'recusado': recusado ?? false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) {
      print('Error agregando entrada de racimo: $e');
      rethrow;
    }
  }

  /// Actualiza los campos editables de una entrada
  Future<void> updateBunchEntryFields({
    required String entryId,
    String? cintaColor,
    String? cuadrilla,
    String? lote,
    bool? recusado,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (cintaColor != null) updates['cintaColor'] = cintaColor;
      if (cuadrilla != null) updates['cuadrilla'] = cuadrilla;
      if (lote != null) updates['lote'] = lote;
      if (recusado != null) updates['recusado'] = recusado;
      if (updates.isEmpty) return;

      await _firestore
          .collection(_bunchEntriesCollection)
          .doc(entryId)
          .update(updates);
    } catch (e) {
      print('Error actualizando campos de entrada: $e');
      rethrow;
    }
  }

  /// Eliminar una entrada de racimo
  Future<void> deleteBunchEntry({required String entryId}) async {
    try {
      await _firestore
          .collection(_bunchEntriesCollection)
          .doc(entryId)
          .delete();
    } catch (e) {
      print('Error eliminando entrada de racimo: $e');
      rethrow;
    }
  }

  /// Stream de entradas por tabla (ordenado por número)
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      streamBunchEntriesByTable(String tableId) {
    return _firestore
        .collection(_bunchEntriesCollection)
        .where('tableId', isEqualTo: tableId)
        .orderBy('number')
        .snapshots()
        .map((snap) => snap.docs);
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
      final doc = await _firestore.collection(_measurementsCollection).add({
        'deviceId': deviceId,
        'weight': weight,
        'unit': unit,
        'sessionId': sessionId,
        // Timestamps: usar serverTimestamp para orden consistente
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        // Timestamp del cliente sólo para debugging/telemetría
        'clientCreatedAt': DateTime.now().toUtc(),
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
    bool preferCache = true,
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
        // Usar solo un orderBy para evitar necesidad de índices compuestos
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots(includeMetadataChanges: preferCache)
        .map((snapshot) => snapshot.docs
            .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
            .toList());
  }

  /// Obtiene la última medición de un dispositivo lo más rápido posible
  /// Prioriza entregar datos desde caché y luego se actualiza con servidor.
  Stream<Map<String, dynamic>?> getLatestMeasurement({
    required String deviceId,
    String? sessionId,
    bool preferCache = true,
  }) {
    Query query = _firestore
        .collection(_measurementsCollection)
        .where('deviceId', isEqualTo: deviceId);

    if (sessionId != null) {
      query = query.where('sessionId', isEqualTo: sessionId);
    }

    return query
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots(includeMetadataChanges: preferCache)
        .map((snapshot) => snapshot.docs.isNotEmpty
            ? {
                ...snapshot.docs.first.data() as Map<String, dynamic>,
                'id': snapshot.docs.first.id
              }
            : null);
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

  /// Elimina múltiples mediciones en lote
  Future<void> deleteMultipleMeasurements(List<String> measurementIds) async {
    try {
      if (measurementIds.isEmpty) return;

      final batch = _firestore.batch();
      for (final id in measurementIds) {
        batch.delete(_firestore.collection(_measurementsCollection).doc(id));
      }
      await batch.commit();
    } catch (e) {
      print('Error eliminando mediciones múltiples: $e');
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

  /// Obtiene la cantidad de entradas de racimo para una tabla
  Future<int> getBunchEntryCount(String tableId) async {
    try {
      final snapshot = await _firestore
          .collection(_bunchEntriesCollection)
          .where('tableId', isEqualTo: tableId)
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      print('Error contando entradas de racimo: $e');
      return 0;
    }
  }

  /// Obtiene el próximo número de racimo (count + 1)
  Future<int> getNextBunchNumber(String tableId) async {
    final count = await getBunchEntryCount(tableId);
    return count + 1;
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

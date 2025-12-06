import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../domain/entities.dart';

/// Servicio de base de datos local SQLite
/// Maneja todas las operaciones de persistencia offline
class DatabaseService {
  static Database? _database;
  static const String _databaseName = 'pruebas_flutter.db';
  static const int _databaseVersion = 1;

  // Nombres de tablas
  static const String _bunchEntriesTable = 'bunch_entries';
  static const String _measurementsTable = 'measurements';
  static const String _sessionsTable = 'sessions';
  static const String _devicesTable = 'devices';

  /// Obtiene la instancia de la base de datos (singleton)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Inicializa la base de datos
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Crea las tablas al instalar por primera vez
  Future<void> _onCreate(Database db, int version) async {
    // Tabla de racimos
    await db.execute('''
      CREATE TABLE $_bunchEntriesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        number INTEGER NOT NULL,
        weightKg REAL NOT NULL,
        weighingTime TEXT NOT NULL,
        cintaColor TEXT DEFAULT '',
        cuadrilla TEXT DEFAULT '',
        lote TEXT DEFAULT '',
        recusado INTEGER DEFAULT 0,
        createdAt TEXT NOT NULL,
        syncedToFirebase INTEGER DEFAULT 0
      )
    ''');

    // Índices para racimos
    await db.execute(
        'CREATE INDEX idx_bunch_number ON $_bunchEntriesTable(number DESC)');
    await db.execute(
        'CREATE INDEX idx_bunch_weighingTime ON $_bunchEntriesTable(weighingTime DESC)');

    // Tabla de mediciones generales
    await db.execute('''
      CREATE TABLE $_measurementsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deviceId TEXT NOT NULL,
        weight REAL NOT NULL,
        unit TEXT NOT NULL,
        sessionId TEXT,
        timestamp TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        metadata TEXT,
        syncedToFirebase INTEGER DEFAULT 0
      )
    ''');

    // Índices para mediciones
    await db.execute(
        'CREATE INDEX idx_measurement_device ON $_measurementsTable(deviceId)');
    await db.execute(
        'CREATE INDEX idx_measurement_created ON $_measurementsTable(createdAt DESC)');

    // Tabla de sesiones
    await db.execute('''
      CREATE TABLE $_sessionsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId TEXT UNIQUE NOT NULL,
        deviceId TEXT NOT NULL,
        animalId TEXT,
        startTime TEXT NOT NULL,
        endTime TEXT,
        measurementCount INTEGER DEFAULT 0,
        status TEXT DEFAULT 'active',
        metadata TEXT,
        syncedToFirebase INTEGER DEFAULT 0
      )
    ''');

    // Tabla de dispositivos
    await db.execute('''
      CREATE TABLE $_devicesTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        lastSeen TEXT NOT NULL
      )
    ''');

    print('✅ Base de datos local creada exitosamente');
  }

  /// Actualiza la base de datos en futuras versiones
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Aquí se agregarán migraciones futuras
    print('🔄 Actualizando BD de v$oldVersion a v$newVersion');
  }

  // ========== OPERACIONES DE RACIMOS ==========

  /// Guarda un racimo
  Future<int> addBunchEntry({
    required int number,
    required double weightKg,
    required DateTime weighingTime,
    String? cintaColor,
    String? cuadrilla,
    String? lote,
    bool? recusado,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    return await db.insert(_bunchEntriesTable, {
      'number': number,
      'weightKg': weightKg,
      'weighingTime': weighingTime.toUtc().toIso8601String(),
      'cintaColor': cintaColor ?? '',
      'cuadrilla': cuadrilla ?? '',
      'lote': lote ?? '',
      'recusado': recusado == true ? 1 : 0,
      'createdAt': now,
      'syncedToFirebase': 0,
    });
  }

  /// Actualiza campos editables de un racimo
  Future<int> updateBunchEntryFields({
    required int id,
    String? cintaColor,
    String? cuadrilla,
    String? lote,
    bool? recusado,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{};

    if (cintaColor != null) updates['cintaColor'] = cintaColor;
    if (cuadrilla != null) updates['cuadrilla'] = cuadrilla;
    if (lote != null) updates['lote'] = lote;
    if (recusado != null) updates['recusado'] = recusado ? 1 : 0;

    if (updates.isEmpty) return 0;

    return await db.update(
      _bunchEntriesTable,
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Elimina un racimo
  Future<int> deleteBunchEntry({required int id}) async {
    final db = await database;
    return await db.delete(
      _bunchEntriesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Obtiene todos los racimos ordenados
  Future<List<Map<String, dynamic>>> getAllBunchEntries({
    int limit = 100,
  }) async {
    final db = await database;
    return await db.query(
      _bunchEntriesTable,
      orderBy: 'number DESC',
      limit: limit,
    );
  }

  /// Stream de racimos (simulado con polling)
  Stream<List<Map<String, dynamic>>> streamBunchEntries({
    int limit = 100,
  }) async* {
    while (true) {
      final bunches = await getAllBunchEntries(limit: limit);
      print('📊 SQLite: ${bunches.length} racimos en la base de datos');
      yield bunches;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // ========== OPERACIONES DE MEDICIONES ==========

  /// Guarda una medición
  Future<int> saveMeasurement({
    required String deviceId,
    required double weight,
    required String unit,
    String? sessionId,
    Map<String, dynamic>? metadata,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    return await db.insert(_measurementsTable, {
      'deviceId': deviceId,
      'weight': weight,
      'unit': unit,
      'sessionId': sessionId,
      'timestamp': now,
      'createdAt': now,
      'metadata': metadata?.toString(),
      'syncedToFirebase': 0,
    });
  }

  /// Obtiene mediciones con filtros
  Future<List<Map<String, dynamic>>> getMeasurements({
    String? sessionId,
    String? deviceId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
  }) async {
    final db = await database;
    String where = '';
    List<dynamic> whereArgs = [];

    if (sessionId != null) {
      where = 'sessionId = ?';
      whereArgs.add(sessionId);
    } else if (deviceId != null) {
      where = 'deviceId = ?';
      whereArgs.add(deviceId);
    }

    return await db.query(
      _measurementsTable,
      where: where.isEmpty ? null : where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'createdAt DESC',
      limit: limit,
    );
  }

  /// Stream de mediciones
  Stream<List<Map<String, dynamic>>> streamMeasurements({
    String? sessionId,
    String? deviceId,
    int limit = 100,
  }) async* {
    while (true) {
      yield await getMeasurements(
        sessionId: sessionId,
        deviceId: deviceId,
        limit: limit,
      );
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // ========== OPERACIONES DE SESIONES ==========

  /// Crea una sesión
  Future<String> createSession({
    required String deviceId,
    String? animalId,
    Map<String, dynamic>? metadata,
  }) async {
    final db = await database;
    final sessionId =
        'session_${DateTime.now().millisecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert(_sessionsTable, {
      'sessionId': sessionId,
      'deviceId': deviceId,
      'animalId': animalId,
      'startTime': now,
      'endTime': null,
      'measurementCount': 0,
      'status': 'active',
      'metadata': metadata?.toString(),
      'syncedToFirebase': 0,
    });

    return sessionId;
  }

  /// Finaliza una sesión
  Future<int> endSession(String sessionId) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    return await db.update(
      _sessionsTable,
      {
        'endTime': now,
        'status': 'completed',
      },
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    );
  }

  // ========== OPERACIONES DE DISPOSITIVOS ==========

  /// Guarda información de un dispositivo
  Future<int> saveDevice(BtDevice device) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    return await db.insert(
      _devicesTable,
      {
        'id': device.id,
        'name': device.name,
        'lastSeen': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ========== MIGRACIÓN DESDE FIREBASE ==========

  /// Importa un racimo desde Firebase
  Future<void> importBunchFromFirebase(Map<String, dynamic> data) async {
    final db = await database;

    // Convertir timestamp de Firebase a DateTime
    DateTime weighingTime;
    if (data['weighingTime'] is String) {
      weighingTime = DateTime.parse(data['weighingTime']);
    } else {
      // Timestamp de Firestore
      weighingTime = (data['weighingTime'] as dynamic).toDate();
    }

    await db.insert(
      _bunchEntriesTable,
      {
        'number': data['number'],
        'weightKg': data['weightKg'],
        'weighingTime': weighingTime.toUtc().toIso8601String(),
        'cintaColor': data['cintaColor'] ?? '',
        'cuadrilla': data['cuadrilla'] ?? '',
        'lote': data['lote'] ?? '',
        'recusado': data['recusado'] == true ? 1 : 0,
        'createdAt': weighingTime.toUtc().toIso8601String(),
        'syncedToFirebase': 1, // Ya está en Firebase
      },
      conflictAlgorithm: ConflictAlgorithm.ignore, // Evitar duplicados
    );
  }

  /// Marca que un racimo fue sincronizado a Firebase
  Future<void> markAsSynced(int id) async {
    final db = await database;
    await db.update(
      _bunchEntriesTable,
      {'syncedToFirebase': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Obtiene racimos no sincronizados
  Future<List<Map<String, dynamic>>> getUnsyncedBunches() async {
    final db = await database;
    return await db.query(
      _bunchEntriesTable,
      where: 'syncedToFirebase = ?',
      whereArgs: [0],
    );
  }

  /// Cierra la base de datos
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

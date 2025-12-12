import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/entities.dart';

/// Servicio SQLite para persistencia local.
/// Define el esquema normalizado solicitado y expone operaciones basicas.
class DatabaseService {
  static const String _databaseName = 'pruebas_flutter.db';
  static const int _databaseVersion =
      4; // Esquema normalizado + descripcion recusado + indices unicos

  // Tablas
  static const String _cuadrillaTable = 'cuadrilla';
  static const String _operariosTable = 'operarios';
  static const String _basculaTable = 'bascula';
  static const String _pesajeTable = 'pesaje';
  static const String _devicesTable = 'devices'; // legado

  Database? _database;

  /// Obtiene instancia singleton de la base de datos.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await _ensureSchema(db);
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createNormalizedSchema(db);
    await _createLegacyTables(db);
    await _createUniqueIndexes(db);
    print('OK. Base de datos local creada con esquema normalizado');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migracion minima: aseguramos tablas/indices del nuevo esquema.
    // Si necesitas migrar datos de tablas previas, hacerlo aqui antes de _createNormalizedSchema.
    // Durante desarrollo, la opcion simple es borrar y recrear la BD usando resetDatabase().
    if (oldVersion < 2) {
      await _createNormalizedSchema(db, ifNotExists: true);
      await _createLegacyTables(db, ifNotExists: true);
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(db, _pesajeTable, 'recusado_desc', 'TEXT');
    }
    if (oldVersion < 4) {
      await _createUniqueIndexes(db);
    }
  }

  Future<void> _ensureSchema(Database db) async {
    await _createNormalizedSchema(db, ifNotExists: true);
    await _createLegacyTables(db, ifNotExists: true);
    await _addColumnIfMissing(db, _pesajeTable, 'recusado_desc', 'TEXT');
    await _createUniqueIndexes(db);
  }

  Future<void> _addColumnIfMissing(
      Database db, String table, String column, String type) async {
    final res = await db.rawQuery('PRAGMA table_info($table)');
    final exists = res.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  Future<void> _createNormalizedSchema(Database db,
      {bool ifNotExists = false}) async {
    final ifClause = ifNotExists ? 'IF NOT EXISTS ' : '';

    await db.execute('''
      CREATE TABLE ${ifClause}${_cuadrillaTable} (
        id_cuadrilla INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${ifClause}${_operariosTable} (
        id_operario INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre_completo TEXT NOT NULL,
        id_cuadrilla INTEGER NOT NULL,
        FOREIGN KEY (id_cuadrilla) REFERENCES $_cuadrillaTable(id_cuadrilla)
      )
    ''');

    await db.execute('''
      CREATE TABLE ${ifClause}${_basculaTable} (
        id_bascula INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        modelo TEXT,
        numero_serie TEXT,
        mac TEXT,
        ubicacion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${ifClause}${_pesajeTable} (
        id_pesaje INTEGER PRIMARY KEY AUTOINCREMENT,
        id_cuadrilla INTEGER NOT NULL,
        id_operario INTEGER NOT NULL,
        id_bascula INTEGER NOT NULL,
        peso REAL NOT NULL,
        fecha_hora TEXT NOT NULL,
        color_cinta TEXT,
        lote TEXT,
        recusado INTEGER NOT NULL DEFAULT 0,
        recusado_desc TEXT,
        FOREIGN KEY (id_cuadrilla) REFERENCES $_cuadrillaTable(id_cuadrilla),
        FOREIGN KEY (id_operario) REFERENCES $_operariosTable(id_operario),
        FOREIGN KEY (id_bascula) REFERENCES $_basculaTable(id_bascula)
      )
    ''');

    await db.execute(
        'CREATE INDEX ${ifClause.isNotEmpty ? 'IF NOT EXISTS ' : ''}idx_pesaje_fecha_hora ON $_pesajeTable(fecha_hora)');
    await db.execute(
        'CREATE INDEX ${ifClause.isNotEmpty ? 'IF NOT EXISTS ' : ''}idx_pesaje_id_cuadrilla ON $_pesajeTable(id_cuadrilla)');
    await db.execute(
        'CREATE INDEX ${ifClause.isNotEmpty ? 'IF NOT EXISTS ' : ''}idx_pesaje_id_operario ON $_pesajeTable(id_operario)');
    await db.execute(
        'CREATE INDEX ${ifClause.isNotEmpty ? 'IF NOT EXISTS ' : ''}idx_pesaje_id_bascula ON $_pesajeTable(id_bascula)');

    // Indices unicos para evitar duplicados por nombre
    await _createUniqueIndexes(db);
  }

  Future<void> _createUniqueIndexes(Database db) async {
    Future<void> _safeCreate(String sql) async {
      try {
        await db.execute(sql);
      } catch (e) {
        print('⚠️ No se pudo crear indice unico ($sql): $e');
      }
    }

    await _safeCreate(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_cuadrilla_nombre_unique ON $_cuadrillaTable(lower(nombre))');
    await _safeCreate(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_operario_nombre_unique ON $_operariosTable(lower(nombre_completo))');
    await _safeCreate(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_bascula_nombre_unique ON $_basculaTable(lower(nombre))');
  }

  Future<void> _createLegacyTables(Database db,
      {bool ifNotExists = false}) async {
    final ifClause = ifNotExists ? 'IF NOT EXISTS ' : '';
    await db.execute('''
      CREATE TABLE ${ifClause}${_devicesTable} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        lastSeen TEXT NOT NULL
      )
    ''');
  }

  // ========== OPERACIONES ESQUEMA NORMALIZADO ==========
  // CUADRILLA
  Future<int> insertCuadrilla({required String nombre}) async {
    final db = await database;
    final normalized = nombre.trim().toUpperCase();
    if (await _existsByName(db, _cuadrillaTable, 'nombre', normalized)) {
      throw Exception('duplicate_cuadrilla');
    }
    return db.insert(_cuadrillaTable, {'nombre': normalized});
  }

  Future<List<Map<String, dynamic>>> getCuadrillas() async {
    final db = await database;
    return db.query(_cuadrillaTable, orderBy: 'id_cuadrilla ASC');
  }

  Future<int> updateCuadrilla({required int id, required String nombre}) async {
    final db = await database;
    final normalized = nombre.trim().toUpperCase();
    // Verificar que no exista otro con el mismo nombre
    final existing = await db.query(
      _cuadrillaTable,
      where: 'LOWER(nombre) = LOWER(?) AND id_cuadrilla != ?',
      whereArgs: [normalized, id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw Exception('duplicate_cuadrilla');
    }
    return db.update(
      _cuadrillaTable,
      {'nombre': normalized},
      where: 'id_cuadrilla = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCuadrilla({required int id}) async {
    final db = await database;
    return db.delete(
      _cuadrillaTable,
      where: 'id_cuadrilla = ?',
      whereArgs: [id],
    );
  }

  // OPERARIOS
  Future<int> insertOperario(
      {required String nombreCompleto, required int idCuadrilla}) async {
    final db = await database;
    final normalized = nombreCompleto.trim().toUpperCase();
    if (await _existsByName(
        db, _operariosTable, 'nombre_completo', normalized)) {
      throw Exception('duplicate_operario');
    }
    return db.insert(_operariosTable, {
      'nombre_completo': normalized,
      'id_cuadrilla': idCuadrilla,
    });
  }

  Future<List<Map<String, dynamic>>> getOperarios({int? idCuadrilla}) async {
    final db = await database;
    return db.query(
      _operariosTable,
      where: idCuadrilla != null ? 'id_cuadrilla = ?' : null,
      whereArgs: idCuadrilla != null ? [idCuadrilla] : null,
      orderBy: 'id_operario ASC',
    );
  }

  Future<int> updateOperario({
    required int id,
    required String nombreCompleto,
    required int idCuadrilla,
  }) async {
    final db = await database;
    final normalized = nombreCompleto.trim().toUpperCase();
    // Verificar que no exista otro con el mismo nombre
    final existing = await db.query(
      _operariosTable,
      where: 'LOWER(nombre_completo) = LOWER(?) AND id_operario != ?',
      whereArgs: [normalized, id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw Exception('duplicate_operario');
    }
    return db.update(
      _operariosTable,
      {
        'nombre_completo': normalized,
        'id_cuadrilla': idCuadrilla,
      },
      where: 'id_operario = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateBascula({
    required int id,
    required String nombre,
    String? modelo,
    String? numeroSerie,
    String? mac,
    String? ubicacion,
  }) async {
    final db = await database;
    final normalized = nombre.trim().toUpperCase();
    // Verificar que no exista otra con el mismo nombre
    final existing = await db.query(
      _basculaTable,
      where: 'LOWER(nombre) = LOWER(?) AND id_bascula != ?',
      whereArgs: [normalized, id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw Exception('duplicate_bascula');
    }
    return db.update(
      _basculaTable,
      {
        'nombre': normalized,
        'modelo': modelo,
        'numero_serie': numeroSerie,
        'mac': mac,
        'ubicacion': ubicacion,
      },
      where: 'id_bascula = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteBascula({required int id}) async {
    final db = await database;
    return db.delete(
      _basculaTable,
      where: 'id_bascula = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteOperario({required int id}) async {
    final db = await database;
    return db.delete(
      _operariosTable,
      where: 'id_operario = ?',
      whereArgs: [id],
    );
  }

  // BASCULA
  Future<int> insertBascula({
    required String nombre,
    String? modelo,
    String? numeroSerie,
    String? mac,
    String? ubicacion,
  }) async {
    final db = await database;
    final normalized = nombre.trim().toUpperCase();
    if (await _existsByName(db, _basculaTable, 'nombre', normalized)) {
      throw Exception('duplicate_bascula');
    }
    return db.insert(_basculaTable, {
      'nombre': normalized,
      'modelo': modelo,
      'numero_serie': numeroSerie,
      'mac': mac,
      'ubicacion': ubicacion,
    });
  }

  Future<List<Map<String, dynamic>>> getBasculas() async {
    final db = await database;
    return db.query(_basculaTable, orderBy: 'id_bascula ASC');
  }

  /// Buscar una báscula por su MAC (dirección de dispositivo Bluetooth)
  Future<Bascula?> getBasculaByMac(String mac) async {
    final db = await database;
    final res = await db.query(
      _basculaTable,
      where: 'LOWER(mac) = LOWER(?)',
      whereArgs: [mac],
      limit: 1,
    );
    if (res.isEmpty) return null;
    return Bascula.fromMap(res.first);
  }

  Future<bool> _existsByName(
      Database db, String table, String column, String value) async {
    final res = await db.query(
      table,
      columns: const ['rowid'],
      where: 'LOWER($column) = LOWER(?)',
      whereArgs: [value],
      limit: 1,
    );
    return res.isNotEmpty;
  }

  // PESAJE
  Future<int> insertPesaje({
    required int idCuadrilla,
    required int idOperario,
    required int idBascula,
    required double peso,
    required DateTime fechaHora,
    String? colorCinta,
    String? lote,
    bool recusado = false,
    String? recusadoDesc,
  }) async {
    final db = await database;
    return db.insert(_pesajeTable, {
      'id_cuadrilla': idCuadrilla,
      'id_operario': idOperario,
      'id_bascula': idBascula,
      'peso': peso,
      'fecha_hora': fechaHora.toIso8601String(),
      'color_cinta': colorCinta,
      'lote': lote,
      'recusado': recusado ? 1 : 0,
      'recusado_desc':
          (recusadoDesc ?? '').trim().isEmpty ? null : recusadoDesc?.trim(),
    });
  }

  Future<List<Map<String, dynamic>>> getPesajes({
    int? idCuadrilla,
    int? idOperario,
    int? idBascula,
    DateTime? desde,
    DateTime? hasta,
    int limit = 200,
  }) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (idCuadrilla != null) {
      whereClauses.add('id_cuadrilla = ?');
      whereArgs.add(idCuadrilla);
    }
    if (idOperario != null) {
      whereClauses.add('id_operario = ?');
      whereArgs.add(idOperario);
    }
    if (idBascula != null) {
      whereClauses.add('id_bascula = ?');
      whereArgs.add(idBascula);
    }
    if (desde != null) {
      whereClauses.add('fecha_hora >= ?');
      whereArgs.add(desde.toIso8601String());
    }
    if (hasta != null) {
      whereClauses.add('fecha_hora <= ?');
      whereArgs.add(hasta.toIso8601String());
    }

    final where = whereClauses.isEmpty ? null : whereClauses.join(' AND ');
    return db.query(
      _pesajeTable,
      where: where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'fecha_hora DESC',
      limit: limit,
    );
  }

  Future<int> updatePesajeRecusado(
      {required int idPesaje, required bool recusado}) async {
    final db = await database;
    return db.update(
      _pesajeTable,
      {'recusado': recusado ? 1 : 0},
      where: 'id_pesaje = ?',
      whereArgs: [idPesaje],
    );
  }

  Future<int> deletePesaje({required int idPesaje}) async {
    final db = await database;
    return db.delete(
      _pesajeTable,
      where: 'id_pesaje = ?',
      whereArgs: [idPesaje],
    );
  }

  // ========== COMPATIBILIDAD LEGADA ==========
  /// Inserta racimo legacy mapeando al nuevo esquema.
  Future<int> addBunchEntry({
    required int number,
    required double weightKg,
    required DateTime weighingTime,
    String? cintaColor,
    String? cuadrilla,
    String? lote,
    bool? recusado,
    String? recusadoDesc,
  }) async {
    final db = await database;

    int idCuadrilla;
    if (cuadrilla != null && cuadrilla.trim().isNotEmpty) {
      final rows = await db
          .query(_cuadrillaTable, where: 'nombre = ?', whereArgs: [cuadrilla]);
      idCuadrilla = rows.isNotEmpty
          ? rows.first['id_cuadrilla'] as int
          : await db.insert(_cuadrillaTable, {'nombre': cuadrilla});
    } else {
      final rows = await db
          .query(_cuadrillaTable, where: 'nombre = ?', whereArgs: ['Default']);
      idCuadrilla = rows.isNotEmpty
          ? rows.first['id_cuadrilla'] as int
          : await db.insert(_cuadrillaTable, {'nombre': 'Default'});
    }

    final opRows = await db.query(_operariosTable,
        where: 'nombre_completo = ? AND id_cuadrilla = ?',
        whereArgs: ['Desconocido', idCuadrilla]);
    final int idOperario = opRows.isNotEmpty
        ? opRows.first['id_operario'] as int
        : await db.insert(_operariosTable,
            {'nombre_completo': 'Desconocido', 'id_cuadrilla': idCuadrilla});

    final bRows = await db
        .query(_basculaTable, where: 'nombre = ?', whereArgs: ['Default']);
    final int idBascula = bRows.isNotEmpty
        ? bRows.first['id_bascula'] as int
        : await db.insert(_basculaTable, {'nombre': 'Default'});

    return db.insert(_pesajeTable, {
      'id_cuadrilla': idCuadrilla,
      'id_operario': idOperario,
      'id_bascula': idBascula,
      'peso': weightKg,
      'fecha_hora': weighingTime.toIso8601String(),
      'color_cinta': cintaColor,
      'lote': lote,
      'recusado': (recusado ?? false) ? 1 : 0,
      'recusado_desc':
          (recusadoDesc ?? '').trim().isEmpty ? null : recusadoDesc?.trim(),
    });
  }

  Future<int> updateBunchEntryFields({
    required int id,
    String? cintaColor,
    String? cuadrilla,
    String? lote,
    bool? recusado,
    String? recusadoDesc,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{};

    if (cintaColor != null) {
      updates['color_cinta'] =
          cintaColor.trim().isEmpty ? null : cintaColor.trim();
    }
    if (lote != null) {
      updates['lote'] = lote.trim().isEmpty ? null : lote.trim();
    }
    if (recusado != null) {
      updates['recusado'] = recusado ? 1 : 0;
    }
    if (recusadoDesc != null) {
      updates['recusado_desc'] =
          recusadoDesc.trim().isEmpty ? null : recusadoDesc.trim();
    }

    if (cuadrilla != null) {
      final name = cuadrilla.trim();
      if (name.isNotEmpty) {
        final rows = await db
            .query(_cuadrillaTable, where: 'nombre = ?', whereArgs: [name]);
        final int idCuadrilla = rows.isNotEmpty
            ? rows.first['id_cuadrilla'] as int
            : await db.insert(_cuadrillaTable, {'nombre': name});
        updates['id_cuadrilla'] = idCuadrilla;
      }
    }

    if (updates.isEmpty) return 0;

    return db.update(
      _pesajeTable,
      updates,
      where: 'id_pesaje = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteBunchEntry({required int id}) async {
    final db = await database;
    return db.delete(
      _pesajeTable,
      where: 'id_pesaje = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getAllBunchEntries({
    int limit = 100,
  }) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.id_pesaje, p.peso, p.fecha_hora, p.color_cinta, p.lote, p.recusado,
              p.recusado_desc,
             c.nombre AS cuadrilla_nombre,
             op.nombre_completo AS operario_nombre,
             b.nombre AS bascula_nombre, b.modelo, b.numero_serie, b.mac, b.ubicacion
      FROM $_pesajeTable p
      LEFT JOIN $_cuadrillaTable c ON p.id_cuadrilla = c.id_cuadrilla
      LEFT JOIN $_operariosTable op ON p.id_operario = op.id_operario
      LEFT JOIN $_basculaTable b ON p.id_bascula = b.id_bascula
      ORDER BY p.fecha_hora DESC
      LIMIT ?
    ''', [limit]);

    return rows
        .map((r) => {
              'id': r['id_pesaje'],
              'number': r['id_pesaje'],
              'weightKg': r['peso'],
              'weighingTime': r['fecha_hora'],
              'cintaColor': r['color_cinta'] ?? '',
              'cuadrilla': r['cuadrilla_nombre'] ?? '',
              'operario': r['operario_nombre'] ?? '',
              'bascula': r['bascula_nombre'] ?? '',
              'bascula_modelo': r['modelo'] ?? '',
              'bascula_numero_serie': r['numero_serie'] ?? '',
              'bascula_mac': r['mac'] ?? '',
              'bascula_ubicacion': r['ubicacion'] ?? '',
              'lote': r['lote'] ?? '',
              'recusado': r['recusado'] ?? 0,
              'recusadoDesc': r['recusado_desc'] ?? '',
              'createdAt': r['fecha_hora'],
              'syncedToFirebase': 0,
            })
        .toList();
  }

  Stream<List<Map<String, dynamic>>> streamBunchEntries({
    int limit = 100,
  }) async* {
    while (true) {
      yield await getAllBunchEntries(limit: limit);
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // ========== OPERACIONES DE DISPOSITIVOS ==========
  Future<int> saveDevice(BtDevice device) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert(
      _devicesTable,
      {
        'id': device.id,
        'name': device.name,
        'lastSeen': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ========== MIGRACION DESDE FIREBASE ==========
  Future<void> importBunchFromFirebase(Map<String, dynamic> data) async {
    // Obsoleto respecto al nuevo esquema
  }

  Future<void> markAsSynced(int id) async {
    // Obsoleto respecto al nuevo esquema
  }

  Future<List<Map<String, dynamic>>> getUnsyncedBunches() async {
    // Obsoleto respecto al nuevo esquema
    return [];
  }

  /// Cierra la base de datos.
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  /// Elimina el archivo de base de datos y recrea el esquema al abrir nuevamente.
  Future<void> resetDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);
    await close();
    await deleteDatabase(path);
  }
}

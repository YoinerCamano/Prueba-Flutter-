import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/entities.dart';

/// Servicio SQLite para persistencia local.
/// Define el esquema normalizado solicitado y expone operaciones basicas.
class DatabaseService {
  static const String _databaseName = 'pruebas_flutter.db';
  static const int _databaseVersion =
  9; // + columna synced_at en pesaje para seguimiento de sincronización

  // Tablas
  static const String _cuadrillaTable = 'cuadrilla';
  static const String _operariosTable = 'operarios';
  static const String _basculaTable = 'bascula';
  static const String _cintaTable = 'cinta';
  static const String _viajePesajeTable = 'viaje_pesaje';
  static const String _pesajeTable = 'pesaje';
  static const String _appSettingsTable = 'app_settings';

  static const List<String> _defaultCintas = [
    'Amarillo',
    'Rojo',
    'Marrón',
    'Blanco',
    'Negro',
    'Morado',
    'Azul',
    'Verde',
    'Naranja',
  ];

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
    await _createJourneyIndexes(db);
    print('OK. Base de datos local creada con esquema normalizado');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migracion minima: aseguramos tablas/indices del nuevo esquema.
    // Si necesitas migrar datos de tablas previas, hacerlo aqui antes de _createNormalizedSchema.
    // Durante desarrollo, la opcion simple es borrar y recrear la BD usando resetDatabase().
    if (oldVersion < 2) {
      await _createNormalizedSchema(db, ifNotExists: true);
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(db, _pesajeTable, 'recusado_desc', 'TEXT');
    }
    if (oldVersion < 4) {
      await _createUniqueIndexes(db);
    }
    if (oldVersion < 5) {
      await _addColumnIfMissing(
          db, _pesajeTable, 'unidad', "TEXT NOT NULL DEFAULT 'kg'");
    }
    if (oldVersion < 6) {
      await _createAppSettingsTable(db, ifNotExists: true);
    }
    if (oldVersion < 7) {
      await _migrateToJourneyModel(db);
      await _dropLegacyTablesIfUnused(db);
    }
    if (oldVersion < 8) {
      await _createCintaTable(db, ifNotExists: true);
      await _seedDefaultCintas(db);
      await _migrateLegacyColorCodes(db);
    }
    if (oldVersion < 9) {
      await _addColumnIfMissing(db, _pesajeTable, 'synced_at', 'TEXT');
    }
  }

  Future<void> _ensureSchema(Database db) async {
    await _createNormalizedSchema(db, ifNotExists: true);
    await _createCintaTable(db, ifNotExists: true);
    await _seedDefaultCintas(db);
    await _createAppSettingsTable(db, ifNotExists: true);
    await _addColumnIfMissing(db, _pesajeTable, 'recusado_desc', 'TEXT');
    await _addColumnIfMissing(
        db, _pesajeTable, 'unidad', "TEXT NOT NULL DEFAULT 'kg'");
    await _createUniqueIndexes(db);
    await _createJourneyIndexes(db);
  }

    Future<void> _addColumnIfMissing(
      DatabaseExecutor db, String table, String column, String type) async {
    final res = await db.rawQuery('PRAGMA table_info($table)');
    final exists = res.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  Future<void> _createNormalizedSchema(DatabaseExecutor db,
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

    await _createCintaTable(db, ifNotExists: ifNotExists);
    await _seedDefaultCintas(db);

    await db.execute('''
      CREATE TABLE ${ifClause}${_viajePesajeTable} (
        id_viaje INTEGER PRIMARY KEY AUTOINCREMENT,
        id_cuadrilla INTEGER NOT NULL,
        id_bascula INTEGER NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT,
        estado TEXT NOT NULL CHECK (estado IN ('abierto', 'cerrado')),
        color_cinta TEXT NOT NULL,
        lote TEXT NOT NULL,
        observacion TEXT,
        FOREIGN KEY (id_cuadrilla) REFERENCES $_cuadrillaTable(id_cuadrilla),
        FOREIGN KEY (id_bascula) REFERENCES $_basculaTable(id_bascula),
        CHECK (
          (estado = 'abierto' AND fecha_fin IS NULL) OR
          (estado = 'cerrado' AND fecha_fin IS NOT NULL)
        )
      )
    ''');

    await db.execute('''
      CREATE TABLE ${ifClause}${_pesajeTable} (
        id_pesaje INTEGER PRIMARY KEY AUTOINCREMENT,
        id_viaje INTEGER NOT NULL,
        numero_racimo INTEGER NOT NULL,
        id_cuadrilla INTEGER NOT NULL,
        id_operario INTEGER NOT NULL,
        id_bascula INTEGER NOT NULL,
        peso REAL NOT NULL,
        unidad TEXT NOT NULL DEFAULT 'kg',
        fecha_hora TEXT NOT NULL,
        color_cinta TEXT,
        lote TEXT,
        recusado INTEGER NOT NULL DEFAULT 0,
        recusado_desc TEXT,
        FOREIGN KEY (id_viaje) REFERENCES $_viajePesajeTable(id_viaje),
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
    await db.execute(
        'CREATE INDEX ${ifClause.isNotEmpty ? 'IF NOT EXISTS ' : ''}idx_pesaje_id_viaje ON $_pesajeTable(id_viaje)');

    await _createJourneyIndexes(db);

    // Indices unicos para evitar duplicados por nombre
    await _createUniqueIndexes(db);
  }

  Future<void> _createJourneyIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_viaje_abierto_por_bascula '
      'ON $_viajePesajeTable(id_bascula) WHERE estado = "abierto"',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_pesaje_viaje_numero '
      'ON $_pesajeTable(id_viaje, numero_racimo)',
    );
  }

  Future<void> _createUniqueIndexes(DatabaseExecutor db) async {
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

  Future<void> _createCintaTable(DatabaseExecutor db,
      {bool ifNotExists = false}) async {
    final ifClause = ifNotExists ? 'IF NOT EXISTS ' : '';
    await db.execute('''
      CREATE TABLE ${ifClause}${_cintaTable} (
        id_cinta INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE
      )
    ''');
  }

  Future<void> _seedDefaultCintas(DatabaseExecutor db) async {
    for (final color in _defaultCintas) {
      await db.rawInsert(
        'INSERT OR IGNORE INTO $_cintaTable(nombre) VALUES (?)',
        [color],
      );
    }
  }

  Future<void> _dropLegacyTablesIfUnused(DatabaseExecutor db) async {
    // Validado en el codigo actual: tablas legacy no tienen referencias activas.
    await db.execute('DROP TABLE IF EXISTS bunch_entries');
    await db.execute('DROP TABLE IF EXISTS measurements');
    await db.execute('DROP TABLE IF EXISTS sessions');
    await db.execute('DROP TABLE IF EXISTS devices');
  }

  Future<void> _migrateToJourneyModel(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('PRAGMA foreign_keys = OFF');
      await _createAppSettingsTable(txn, ifNotExists: true);

      await txn.execute('''
        CREATE TABLE IF NOT EXISTS $_viajePesajeTable (
          id_viaje INTEGER PRIMARY KEY AUTOINCREMENT,
          id_cuadrilla INTEGER NOT NULL,
          id_bascula INTEGER NOT NULL,
          fecha_inicio TEXT NOT NULL,
          fecha_fin TEXT,
          estado TEXT NOT NULL CHECK (estado IN ('abierto', 'cerrado')),
          color_cinta TEXT NOT NULL,
          lote TEXT NOT NULL,
          observacion TEXT,
          FOREIGN KEY (id_cuadrilla) REFERENCES $_cuadrillaTable(id_cuadrilla),
          FOREIGN KEY (id_bascula) REFERENCES $_basculaTable(id_bascula),
          CHECK (
            (estado = 'abierto' AND fecha_fin IS NULL) OR
            (estado = 'cerrado' AND fecha_fin IS NOT NULL)
          )
        )
      ''');

      await txn.execute('''
        CREATE TABLE IF NOT EXISTS ${_pesajeTable}_new (
          id_pesaje INTEGER PRIMARY KEY AUTOINCREMENT,
          id_viaje INTEGER NOT NULL,
          numero_racimo INTEGER NOT NULL,
          id_cuadrilla INTEGER NOT NULL,
          id_operario INTEGER NOT NULL,
          id_bascula INTEGER NOT NULL,
          peso REAL NOT NULL,
          unidad TEXT NOT NULL DEFAULT 'kg',
          fecha_hora TEXT NOT NULL,
          color_cinta TEXT,
          lote TEXT,
          recusado INTEGER NOT NULL DEFAULT 0,
          recusado_desc TEXT,
          FOREIGN KEY (id_viaje) REFERENCES $_viajePesajeTable(id_viaje),
          FOREIGN KEY (id_cuadrilla) REFERENCES $_cuadrillaTable(id_cuadrilla),
          FOREIGN KEY (id_operario) REFERENCES $_operariosTable(id_operario),
          FOREIGN KEY (id_bascula) REFERENCES $_basculaTable(id_bascula)
        )
      ''');

      final oldRows = await txn.query(_pesajeTable, orderBy: 'id_pesaje ASC');
      for (final row in oldRows) {
        final color = _normalizeColorText((row['color_cinta'] ?? '').toString());
        final lote = (row['lote'] ?? '').toString().trim().isEmpty
            ? 'sin lote'
            : (row['lote'] ?? '').toString().trim().toLowerCase();
        final fecha = (row['fecha_hora'] ?? DateTime.now().toIso8601String())
            .toString();
        final idViaje = await txn.insert(_viajePesajeTable, {
          'id_cuadrilla': row['id_cuadrilla'],
          'id_bascula': row['id_bascula'],
          'fecha_inicio': fecha,
          'fecha_fin': fecha,
          'estado': 'cerrado',
          'color_cinta': color,
          'lote': lote,
          'observacion': 'migrado_v7',
        });

        await txn.insert('${_pesajeTable}_new', {
          'id_pesaje': row['id_pesaje'],
          'id_viaje': idViaje,
          'numero_racimo': 1,
          'id_cuadrilla': row['id_cuadrilla'],
          'id_operario': row['id_operario'],
          'id_bascula': row['id_bascula'],
          'peso': row['peso'],
          'unidad': row['unidad'] ?? 'kg',
          'fecha_hora': fecha,
          'color_cinta': color,
          'lote': lote,
          'recusado': row['recusado'] ?? 0,
          'recusado_desc': row['recusado_desc'],
        });
      }

      await txn.execute('DROP TABLE IF EXISTS $_pesajeTable');
      await txn.execute('ALTER TABLE ${_pesajeTable}_new RENAME TO $_pesajeTable');

      await txn.execute('CREATE INDEX IF NOT EXISTS idx_pesaje_fecha_hora ON $_pesajeTable(fecha_hora)');
      await txn.execute('CREATE INDEX IF NOT EXISTS idx_pesaje_id_cuadrilla ON $_pesajeTable(id_cuadrilla)');
      await txn.execute('CREATE INDEX IF NOT EXISTS idx_pesaje_id_operario ON $_pesajeTable(id_operario)');
      await txn.execute('CREATE INDEX IF NOT EXISTS idx_pesaje_id_bascula ON $_pesajeTable(id_bascula)');
      await txn.execute('CREATE INDEX IF NOT EXISTS idx_pesaje_id_viaje ON $_pesajeTable(id_viaje)');

      await _createUniqueIndexes(txn);
      await _createJourneyIndexes(txn);
      await _createCintaTable(txn, ifNotExists: true);
      await _seedDefaultCintas(txn);
      await txn.execute('PRAGMA foreign_keys = ON');
    });
  }

  Future<void> _createAppSettingsTable(DatabaseExecutor db,
      {bool ifNotExists = false}) async {
    final ifClause = ifNotExists ? 'IF NOT EXISTS ' : '';
    await db.execute('''
      CREATE TABLE ${ifClause}${_appSettingsTable} (
        k TEXT PRIMARY KEY,
        v TEXT NOT NULL
      )
    ''');
  }

  Future<void> _migrateLegacyColorCodes(Database db) async {
    await db.transaction((txn) async {
      await _createCintaTable(txn, ifNotExists: true);
      await _seedDefaultCintas(txn);

      final viajes = await txn.query(
        _viajePesajeTable,
        columns: const ['id_viaje', 'color_cinta'],
      );
      for (final row in viajes) {
        final idViaje = row['id_viaje'] as int;
        final original = (row['color_cinta'] ?? '').toString();
        final normalized = _normalizeColorText(original);
        await _ensureCintaExists(txn, normalized);
        if (normalized != original) {
          await txn.update(
            _viajePesajeTable,
            {'color_cinta': normalized},
            where: 'id_viaje = ?',
            whereArgs: [idViaje],
          );
        }
      }

      final pesajes = await txn.query(
        _pesajeTable,
        columns: const ['id_pesaje', 'color_cinta'],
      );
      for (final row in pesajes) {
        final idPesaje = row['id_pesaje'] as int;
        final original = (row['color_cinta'] ?? '').toString();
        if (original.trim().isEmpty) continue;
        final normalized = _normalizeColorText(original);
        await _ensureCintaExists(txn, normalized);
        if (normalized != original) {
          await txn.update(
            _pesajeTable,
            {'color_cinta': normalized},
            where: 'id_pesaje = ?',
            whereArgs: [idPesaje],
          );
        }
      }

      final preferredRows = await txn.query(
        _appSettingsTable,
        columns: const ['v'],
        where: 'k = ?',
        whereArgs: const ['preferred_color'],
        limit: 1,
      );
      if (preferredRows.isNotEmpty) {
        final original = (preferredRows.first['v'] ?? '').toString();
        if (original.trim().isNotEmpty) {
          final normalized = _normalizeColorText(original);
          await _ensureCintaExists(txn, normalized);
          if (normalized != original) {
            await txn.update(
              _appSettingsTable,
              {'v': normalized},
              where: 'k = ?',
              whereArgs: const ['preferred_color'],
            );
          }
        }
      }
    });
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

  Future<List<Map<String, dynamic>>> getCintas() async {
    final db = await database;
    return db.query(_cintaTable, orderBy: 'id_cinta ASC');
  }

  Future<List<String>> getCintaColors() async {
    final rows = await getCintas();
    return rows
        .map((row) => (row['nombre'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<int> insertCintaColor(String nombre) async {
    final db = await database;
    final normalized = _normalizeColorText(nombre);
    await db.rawInsert(
      'INSERT OR IGNORE INTO $_cintaTable(nombre) VALUES (?)',
      [normalized],
    );
    final rows = await db.query(
      _cintaTable,
      columns: const ['id_cinta'],
      where: 'LOWER(nombre) = LOWER(?)',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('No fue posible insertar la cinta: $nombre');
    }
    return rows.first['id_cinta'] as int;
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

  String _normalizeKey(String raw) {
    return raw
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .trim();
  }

  String _capitalizeWords(String raw) {
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) {
      if (part.length == 1) return part.toUpperCase();
      return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
    }).join(' ');
  }

  String _normalizeColorText(String raw) {
    final key = _normalizeKey(raw);
    if (key.isEmpty) return 'Sin color';

    const canonical = {
      'amarillo': 'Amarillo',
      'rojo': 'Rojo',
      'marron': 'Marrón',
      'blanco': 'Blanco',
      'negro': 'Negro',
      'morado': 'Morado',
      'azul': 'Azul',
      'verde': 'Verde',
      'naranja': 'Naranja',
      'white': 'Blanco',
      'black': 'Negro',
      'brown': 'Marrón',
      'purple': 'Morado',
      'orange': 'Naranja',
      'blue': 'Azul',
      '7': 'Rojo',
      '8': 'Marrón',
      '10': 'Azul',
      '11': 'Verde',
      '12': 'Azul',
      'azul oscuro': 'Azul',
      'cian': 'Azul',
    };

    final mapped = canonical[key];
    if (mapped != null) return mapped;
    return _capitalizeWords(raw);
  }

  Future<void> _ensureCintaExists(DatabaseExecutor db, String colorName) async {
    final normalized = _normalizeColorText(colorName);
    if (normalized.trim().isEmpty || normalized == 'Sin color') return;
    await db.rawInsert(
      'INSERT OR IGNORE INTO $_cintaTable(nombre) VALUES (?)',
      [normalized],
    );
  }

  Future<int> crearViajePesaje({
    required int idCuadrilla,
    required int idBascula,
    required String colorCinta,
    required String lote,
    String? observacion,
    DateTime? fechaInicio,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final abierto = await txn.query(
        _viajePesajeTable,
        columns: const ['id_viaje'],
        where: 'id_bascula = ? AND estado = ?',
        whereArgs: [idBascula, 'abierto'],
        limit: 1,
      );
      if (abierto.isNotEmpty) {
        throw StateError('Ya existe un viaje abierto para esta bascula');
      }

      final normalizedColor = _normalizeColorText(colorCinta);
      await _ensureCintaExists(txn, normalizedColor);

      return txn.insert(_viajePesajeTable, {
        'id_cuadrilla': idCuadrilla,
        'id_bascula': idBascula,
        'fecha_inicio': (fechaInicio ?? DateTime.now()).toIso8601String(),
        'fecha_fin': null,
        'estado': 'abierto',
        'color_cinta': normalizedColor,
        'lote': lote.trim().isEmpty ? 'sin lote' : lote.trim().toLowerCase(),
        'observacion': (observacion ?? '').trim().isEmpty
            ? null
            : observacion?.trim(),
      });
    });
  }

  Future<Map<String, dynamic>?> obtenerViajeActivoPorBascula(int idBascula) async {
    final db = await database;
    final rows = await db.query(
      _viajePesajeTable,
      where: 'id_bascula = ? AND estado = ?',
      whereArgs: [idBascula, 'abierto'],
      limit: 1,
      orderBy: 'id_viaje DESC',
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> obtenerSiguienteNumeroRacimo({
    required DatabaseExecutor executor,
    required int idViaje,
  }) async {
    final rows = await executor.rawQuery(
      'SELECT COALESCE(MAX(numero_racimo), 0) + 1 AS next_num FROM $_pesajeTable WHERE id_viaje = ?',
      [idViaje],
    );
    return (rows.first['next_num'] as int?) ?? 1;
  }

  Future<void> finalizarViajePesaje({
    required int idViaje,
    DateTime? fechaFin,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        _viajePesajeTable,
        where: 'id_viaje = ?',
        whereArgs: [idViaje],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Viaje no encontrado');
      }
      final estado = (rows.first['estado'] ?? '').toString();
      if (estado == 'cerrado') {
        throw StateError('El viaje ya esta cerrado');
      }

      await txn.update(
        _viajePesajeTable,
        {
          'estado': 'cerrado',
          'fecha_fin': (fechaFin ?? DateTime.now()).toIso8601String(),
        },
        where: 'id_viaje = ?',
        whereArgs: [idViaje],
      );
    });
  }

  // PESAJE
  Future<int> insertPesaje({
    required int idCuadrilla,
    required int idOperario,
    required int idBascula,
    required double peso,
    String unidad = 'kg',
    required DateTime fechaHora,
    String? colorCinta,
    String? lote,
    bool recusado = false,
    String? recusadoDesc,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final viaje = await txn.query(
        _viajePesajeTable,
        where: 'id_bascula = ? AND estado = ?',
        whereArgs: [idBascula, 'abierto'],
        limit: 1,
      );
      if (viaje.isEmpty) {
        throw StateError('No existe un viaje abierto para esta bascula');
      }

      final viajeActivo = viaje.first;
      final idViaje = viajeActivo['id_viaje'] as int;
      final numeroRacimo = await obtenerSiguienteNumeroRacimo(
        executor: txn,
        idViaje: idViaje,
      );

      final normalizedColor = _normalizeColorText(
        colorCinta ?? (viajeActivo['color_cinta'] ?? 'Sin color').toString(),
      );
      await _ensureCintaExists(txn, normalizedColor);

      return txn.insert(_pesajeTable, {
        'id_viaje': idViaje,
        'numero_racimo': numeroRacimo,
        'id_cuadrilla': idCuadrilla,
        'id_operario': idOperario,
        'id_bascula': idBascula,
        'peso': peso,
        'unidad': unidad,
        'fecha_hora': fechaHora.toIso8601String(),
        'color_cinta': normalizedColor,
        'lote': lote ?? viajeActivo['lote'],
        'recusado': recusado ? 1 : 0,
        'recusado_desc':
            (recusadoDesc ?? '').trim().isEmpty ? null : recusadoDesc?.trim(),
      });
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

    return db.transaction((txn) async {
      int idCuadrilla;
      if (cuadrilla != null && cuadrilla.trim().isNotEmpty) {
        final rows = await txn.query(
          _cuadrillaTable,
          where: 'nombre = ?',
          whereArgs: [cuadrilla],
        );
        idCuadrilla = rows.isNotEmpty
            ? rows.first['id_cuadrilla'] as int
            : await txn.insert(_cuadrillaTable, {'nombre': cuadrilla});
      } else {
        final rows = await txn.query(
          _cuadrillaTable,
          where: 'nombre = ?',
          whereArgs: ['Default'],
        );
        idCuadrilla = rows.isNotEmpty
            ? rows.first['id_cuadrilla'] as int
            : await txn.insert(_cuadrillaTable, {'nombre': 'Default'});
      }

      final opRows = await txn.query(
        _operariosTable,
        where: 'nombre_completo = ? AND id_cuadrilla = ?',
        whereArgs: ['Desconocido', idCuadrilla],
      );
      final int idOperario = opRows.isNotEmpty
          ? opRows.first['id_operario'] as int
          : await txn.insert(_operariosTable,
              {'nombre_completo': 'Desconocido', 'id_cuadrilla': idCuadrilla});

      final bRows = await txn.query(
        _basculaTable,
        where: 'nombre = ?',
        whereArgs: ['Default'],
      );
      final int idBascula = bRows.isNotEmpty
          ? bRows.first['id_bascula'] as int
          : await txn.insert(_basculaTable, {'nombre': 'Default'});

      final idViaje = await txn.insert(_viajePesajeTable, {
        'id_cuadrilla': idCuadrilla,
        'id_bascula': idBascula,
        'fecha_inicio': weighingTime.toIso8601String(),
        'fecha_fin': weighingTime.toIso8601String(),
        'estado': 'cerrado',
        'color_cinta': _normalizeColorText(cintaColor ?? ''),
        'lote': lote?.trim().isNotEmpty == true
            ? lote!.trim().toLowerCase()
            : 'sin lote',
      });

      await _ensureCintaExists(txn, (cintaColor ?? '').trim());

      return txn.insert(_pesajeTable, {
        'id_viaje': idViaje,
        'numero_racimo': number > 0 ? number : 1,
        'id_cuadrilla': idCuadrilla,
        'id_operario': idOperario,
        'id_bascula': idBascula,
        'peso': weightKg,
        'unidad': 'kg',
        'fecha_hora': weighingTime.toIso8601String(),
        'color_cinta': _normalizeColorText(cintaColor ?? ''),
        'lote': lote,
        'recusado': (recusado ?? false) ? 1 : 0,
        'recusado_desc':
            (recusadoDesc ?? '').trim().isEmpty ? null : recusadoDesc?.trim(),
      });
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
      final normalizedColor =
          cintaColor.trim().isEmpty ? null : _normalizeColorText(cintaColor);
      updates['color_cinta'] = normalizedColor;
      if (normalizedColor != null) {
        await _ensureCintaExists(db, normalizedColor);
      }
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
      SELECT p.id_pesaje, p.id_viaje, p.numero_racimo, p.peso, p.unidad, p.fecha_hora, p.color_cinta, p.lote, p.recusado,
             p.synced_at,
              p.recusado_desc,
             v.estado AS viaje_estado,
             c.nombre AS cuadrilla_nombre,
             op.nombre_completo AS operario_nombre,
             b.nombre AS bascula_nombre, b.modelo, b.numero_serie, b.mac, b.ubicacion
      FROM $_pesajeTable p
      LEFT JOIN $_viajePesajeTable v ON p.id_viaje = v.id_viaje
      LEFT JOIN $_cuadrillaTable c ON p.id_cuadrilla = c.id_cuadrilla
      LEFT JOIN $_operariosTable op ON p.id_operario = op.id_operario
      LEFT JOIN $_basculaTable b ON p.id_bascula = b.id_bascula
      ORDER BY p.fecha_hora DESC
      LIMIT ?
    ''', [limit]);

    return rows
        .map((r) => {
              'id': r['id_pesaje'],
            'idViaje': r['id_viaje'],
            'number': r['numero_racimo'] ?? r['id_pesaje'],
              'weightKg': r['peso'],
            'unidad': r['unidad'] ?? 'kg',
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
              'viajeEstado': r['viaje_estado'] ?? '',
              'recusado': r['recusado'] ?? 0,
              'recusadoDesc': r['recusado_desc'] ?? '',
              'createdAt': r['fecha_hora'],
              'syncedAt': r['synced_at'],
              'synced': (r['synced_at'] != null) ? 1 : 0,
              'syncedToFirebase': (r['synced_at'] != null) ? 1 : 0,
            })
        .toList();
  }

  Future<List<Map<String, dynamic>>> getViajesDelDia({
    DateTime? day,
  }) async {
    final db = await database;
    final base = (day ?? DateTime.now()).toLocal();
    final start = DateTime(base.year, base.month, base.day);
    final end = start.add(const Duration(days: 1));

    final rows = await db.rawQuery('''
      SELECT v.id_viaje, v.id_cuadrilla, v.id_bascula, v.fecha_inicio, v.fecha_fin,
             v.estado, v.color_cinta, v.lote, v.observacion,
             c.nombre AS cuadrilla_nombre,
             b.nombre AS bascula_nombre,
             COUNT(p.id_pesaje) AS total_pesajes
      FROM $_viajePesajeTable v
      LEFT JOIN $_cuadrillaTable c ON c.id_cuadrilla = v.id_cuadrilla
      LEFT JOIN $_basculaTable b ON b.id_bascula = v.id_bascula
      LEFT JOIN $_pesajeTable p ON p.id_viaje = v.id_viaje
      WHERE v.fecha_inicio >= ? AND v.fecha_inicio < ?
      GROUP BY v.id_viaje
      ORDER BY v.fecha_inicio DESC
    ''', [start.toIso8601String(), end.toIso8601String()]);

    return rows;
  }

  Future<List<Map<String, dynamic>>> getPesajesPorViaje({
    required int idViaje,
  }) async {
    final db = await database;
    return db.rawQuery('''
      SELECT p.id_pesaje, p.id_viaje, p.numero_racimo, p.peso, p.unidad,
             p.fecha_hora, p.color_cinta, p.lote, p.recusado, p.recusado_desc,
             op.nombre_completo AS operario_nombre
      FROM $_pesajeTable p
      LEFT JOIN $_operariosTable op ON op.id_operario = p.id_operario
      WHERE p.id_viaje = ?
      ORDER BY p.numero_racimo ASC, p.fecha_hora ASC
    ''', [idViaje]);
  }

  Stream<List<Map<String, dynamic>>> streamViajesDelDia({
    DateTime? day,
  }) async* {
    while (true) {
      yield await getViajesDelDia(day: day);
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Stream<List<Map<String, dynamic>>> streamBunchEntries({
    int limit = 100,
  }) async* {
    while (true) {
      yield await getAllBunchEntries(limit: limit);
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // ========== PREFERENCIAS APP ==========
  Future<void> setPreferredWeightUnit(String unit) async {
    final normalized = unit.trim().toLowerCase();
    if (normalized != 'kg' && normalized != 'lb') {
      throw ArgumentError('Unidad inválida: $unit');
    }

    final db = await database;
    await db.insert(
      _appSettingsTable,
      {'k': 'preferred_weight_unit', 'v': normalized},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> getPreferredWeightUnit() async {
    final db = await database;
    final rows = await db.query(
      _appSettingsTable,
      columns: const ['v'],
      where: 'k = ?',
      whereArgs: const ['preferred_weight_unit'],
      limit: 1,
    );

    if (rows.isEmpty) return 'kg';
    final value = (rows.first['v'] as String?)?.toLowerCase();
    return value == 'lb' ? 'lb' : 'kg';
  }

  Future<void> setPreferredColor(String? colorCode) async {
    final db = await database;
    if (colorCode == null || colorCode.isEmpty) {
      await db.delete(_appSettingsTable,
          where: 'k = ?', whereArgs: const ['preferred_color']);
      return;
    }
    await db.insert(
      _appSettingsTable,
      {'k': 'preferred_color', 'v': colorCode},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getPreferredColor() async {
    final db = await database;
    final rows = await db.query(
      _appSettingsTable,
      columns: const ['v'],
      where: 'k = ?',
      whereArgs: const ['preferred_color'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['v'] as String?;
  }

  Future<void> setAutoSaveEnabled(bool enabled) async {
    final db = await database;
    await db.insert(
      _appSettingsTable,
      {'k': 'auto_save_enabled', 'v': enabled ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> getAutoSaveEnabled() async {
    final db = await database;
    final rows = await db.query(
      _appSettingsTable,
      columns: const ['v'],
      where: 'k = ?',
      whereArgs: const ['auto_save_enabled'],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final value = (rows.first['v'] as String?)?.trim() ?? '0';
    return value == '1' || value.toLowerCase() == 'true';
  }

  Future<void> setManualSaveEnabled(bool enabled) async {
    final db = await database;
    await db.insert(
      _appSettingsTable,
      {'k': 'manual_save_enabled', 'v': enabled ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> getManualSaveEnabled() async {
    final db = await database;
    final rows = await db.query(
      _appSettingsTable,
      columns: const ['v'],
      where: 'k = ?',
      whereArgs: const ['manual_save_enabled'],
      limit: 1,
    );
    if (rows.isEmpty) return true;
    final value = (rows.first['v'] as String?)?.trim() ?? '1';
    return value == '1' || value.toLowerCase() == 'true';
  }

  Future<void> setMinimumSaveWeight(double value) async {
    if (value < 0) {
      throw ArgumentError('El peso minimo no puede ser negativo');
    }
    final db = await database;
    await db.insert(
      _appSettingsTable,
      {'k': 'minimum_save_weight', 'v': value.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<double> getMinimumSaveWeight() async {
    final db = await database;
    final rows = await db.query(
      _appSettingsTable,
      columns: const ['v'],
      where: 'k = ?',
      whereArgs: const ['minimum_save_weight'],
      limit: 1,
    );
    if (rows.isEmpty) return 1.0;
    final parsed =
        double.tryParse((rows.first['v'] as String?)?.trim() ?? '');
    return (parsed == null || parsed < 0) ? 1.0 : parsed;
  }

  Future<void> setUnloadThreshold(double value) async {
    if (value < 0) {
      throw ArgumentError('El umbral de descarga no puede ser negativo');
    }
    final db = await database;
    await db.insert(
      _appSettingsTable,
      {'k': 'unload_threshold', 'v': value.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<double> getUnloadThreshold() async {
    final db = await database;
    final rows = await db.query(
      _appSettingsTable,
      columns: const ['v'],
      where: 'k = ?',
      whereArgs: const ['unload_threshold'],
      limit: 1,
    );
    if (rows.isEmpty) return 0.5;
    final parsed =
        double.tryParse((rows.first['v'] as String?)?.trim() ?? '');
    return (parsed == null || parsed < 0) ? 0.5 : parsed;
  }

  // ========== MIGRACION DESDE FIREBASE ==========
  Future<void> importBunchFromFirebase(Map<String, dynamic> data) async {
    // Obsoleto respecto al nuevo esquema
  }

  /// Marca un pesaje como sincronizado con la fecha/hora actual.
  Future<void> markAsSynced(int id) async {
    final db = await database;
    await db.update(
      _pesajeTable,
      {'synced_at': DateTime.now().toIso8601String()},
      where: 'id_pesaje = ?',
      whereArgs: [id],
    );
  }

  /// Marca múltiples pesajes como sincronizados en una transacción.
  Future<void> markBatchAsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          _pesajeTable,
          {'synced_at': now},
          where: 'id_pesaje = ?',
          whereArgs: [id],
        );
      }
    });
  }

  /// Devuelve los pesajes pendientes de sincronización (synced_at IS NULL).
  Future<List<Map<String, dynamic>>> getUnsyncedBunches() async {
    final db = await database;
    return db.query(
      _pesajeTable,
      where: 'synced_at IS NULL',
      orderBy: 'fecha_hora ASC',
    );
  }

  /// Cuenta los pesajes pendientes de sincronización.
  Future<int> countUnsyncedBunches() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM $_pesajeTable WHERE synced_at IS NULL',
    );
    return Sqflite.firstIntValue(result) ?? 0;
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

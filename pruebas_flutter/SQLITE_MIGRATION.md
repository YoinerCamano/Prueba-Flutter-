# Migración a Base de Datos Local (SQLite)

## 🎯 Cambios Realizados

La aplicación ahora usa **SQLite** como base de datos principal, funcionando completamente **offline** sin depender de conexión a internet.

### ✅ Ventajas
- ✅ **100% offline** - No requiere internet para funcionar
- ✅ **Rápido** - Consultas instantáneas desde el dispositivo
- ✅ **Confiable** - No depende de conexión de red
- ✅ **Capacidad** - Maneja millones de registros sin problema
- ✅ **Firebase opcional** - Respaldo automático cuando hay conexión

### 📊 Estructura de la Base de Datos

#### Tablas SQLite

1. **bunch_entries** (Racimos)
   - `id`: INTEGER PRIMARY KEY AUTOINCREMENT
   - `number`: INTEGER (número de racimo)
   - `weightKg`: REAL (peso en kg)
   - `weighingTime`: TEXT (fecha/hora ISO 8601)
   - `cintaColor`: TEXT (color de cinta)
   - `cuadrilla`: TEXT (cuadrilla)
   - `lote`: TEXT (lote)
   - `recusado`: INTEGER (0=no, 1=sí)
   - `createdAt`: TEXT (timestamp)
   - `syncedToFirebase`: INTEGER (0=no, 1=sí)

2. **measurements** (Mediciones generales)
   - Similar estructura para historial de pesos

3. **sessions** (Sesiones de pesaje)
   - Seguimiento de sesiones de medición

4. **devices** (Dispositivos Bluetooth)
   - Información de básculas conectadas

## 🔄 Migración de Datos Existentes

### Paso 1: Verificar Conexión a Internet

Asegúrate de tener **conexión a internet** antes de migrar (para descargar datos de Firebase).

### Paso 2: Ejecutar Herramienta de Migración

La app incluye una herramienta para transferir todos tus datos de Firebase a SQLite:

```dart
// Opción 1: Desde código
import 'package:pruebas_flutter/utils/firebase_to_sqlite_migration.dart';

// Navegar a la página de migración
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => MigrationPage()),
);

// Opción 2: Desde terminal/script
final migration = FirebaseToSQLiteMigration();
await migration.migrateAll();
```

### Paso 3: Agregar Botón de Migración (Temporal)

Para facilitar la migración, puedes agregar temporalmente un botón en `HomePage`:

```dart
// En el AppBar o FloatingActionButton de HomePage
IconButton(
  icon: Icon(Icons.cloud_download),
  tooltip: 'Migrar datos de Firebase',
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MigrationPage()),
    );
  },
)
```

### Paso 4: Ejecutar Migración

1. Abrir la app
2. Presionar el botón "Migrar datos"
3. Esperar a que complete (puede tomar varios minutos)
4. Ver resumen de datos migrados

**⚠️ IMPORTANTE**: Solo ejecutar UNA VEZ. Los datos no se eliminarán de Firebase.

## 🚀 Uso Después de la Migración

### Guardado Automático

Los racimos se guardan automáticamente en SQLite:

```dart
// HomePage - Al presionar "Guardar Pesaje"
final databaseService = DatabaseProvider.of(context);
await databaseService.addBunchEntry(
  number: nextNumber,
  weightKg: weightKg,
  weighingTime: DateTime.now(),
  // ...
);
```

### Respaldo Opcional en Firebase

Firebase ahora es **opcional**. Si hay conexión, los datos se respaldan automáticamente:

```dart
// Respaldo en background (no bloquea)
firebaseService?.addBunchEntry(...).catchError((e) {
  print('⚠️ No se pudo respaldar (OK, está en local)');
});
```

### Visualización de Datos

`BunchTablePage` ahora lee de SQLite:

```dart
final databaseService = DatabaseProvider.of(context);
stream: databaseService.streamBunchEntries(limit: 1000)
```

## 📱 Ubicación de la Base de Datos

La base de datos SQLite se guarda en:

- **Android**: `/data/data/com.example.pruebas_flutter/databases/pruebas_flutter.db`
- **iOS**: `Library/Application Support/pruebas_flutter.db`

## 🔧 Mantenimiento

### Ver Datos No Sincronizados

```dart
final unsynced = await databaseService.getUnsyncedBunches();
print('Racimos pendientes de respaldo: ${unsynced.length}');
```

### Forzar Sincronización

```dart
// Obtener racimos no sincronizados
final unsynced = await databaseService.getUnsyncedBunches();

// Subir a Firebase
for (final bunch in unsynced) {
  await firebaseService?.addBunchEntry(
    tableId: deviceId,
    number: bunch['number'],
    weightKg: bunch['weightKg'],
    // ...
  );
  
  // Marcar como sincronizado
  await databaseService.markAsSynced(bunch['id']);
}
```

## ❓ Preguntas Frecuentes

### ¿Qué pasa si no tengo internet?

✅ La app funciona 100% normal. Los datos se guardan localmente y se respaldarán cuando haya conexión.

### ¿Puedo seguir usando Firebase?

✅ Sí, Firebase sigue funcionando como respaldo opcional. No afecta el funcionamiento principal.

### ¿Se perderán mis datos de Firebase?

❌ No. La migración solo **copia** los datos, no los elimina de Firebase.

### ¿Cuántos datos puede manejar SQLite?

✅ SQLite maneja millones de registros sin problema. Para tu caso de uso (racimos de banano), podrías almacenar décadas de datos.

### ¿Puedo migrar varias veces?

⚠️ Sí, pero puede crear duplicados. La herramienta usa `ConflictAlgorithm.ignore` para evitarlo cuando sea posible.

## 🐛 Solución de Problemas

### Error: "No se puede conectar a Firebase"

✅ Normal si no hay internet. La app funciona sin Firebase.

### Error: "Database is locked"

Cerrar y reabrir la app. SQLite solo permite una conexión a la vez.

### Los datos no aparecen

Verificar que la migración se completó exitosamente. Revisar logs en consola.

## 📝 Notas Técnicas

- **ORM**: No usamos ORM, solo SQL directo para máxima eficiencia
- **Streams**: Implementados con polling cada 500ms
- **Índices**: Creados automáticamente en `number` y `weighingTime`
- **Timestamps**: Formato ISO 8601 (UTC)
- **Booleanos**: SQLite usa INTEGER (0=false, 1=true)

## 🔜 Próximos Pasos

1. Ejecutar migración de datos
2. Probar guardado offline
3. Verificar visualización en BunchTablePage
4. Opcional: Remover código de Firebase si no necesitas respaldo

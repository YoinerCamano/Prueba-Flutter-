# 📊 Flujo de Datos de Racimos

## 1️⃣ CUANDO PRESIONAS EL BOTÓN "GUARDAR" EN HOMEPAGE

```
Home Page (home_page.dart)
    ↓ Botón GUARDAR presionado
    ↓
_saveWeighing(BuildContext context, conn.Connected state)
    ↓ Extrae peso de la báscula
    ↓
firebaseService.addBunchEntry(
    tableId: tableId,        ← ID de la tabla de Firebase
    number: nextNumber,      ← Número secuencial (1, 2, 3...)
    weightKg: weightKg,      ← Peso en kg
    weighingTime: DateTime.now()
)
```

## 2️⃣ GUARDADO DE DATOS - addBunchEntry()

**Ubicación:** `lib/data/firebase/firebase_service.dart`

```
FirebaseService.addBunchEntry()
    │
    ├─ PASO 1: GUARDAR LOCALMENTE (INSTANTÁNEO) ⚡
    │   │
    │   └─ LocalStorageService.saveBunchEntry()
    │       │
    │       └─ Base de datos SQLite local
    │           ├─ Tabla: "bunch_entries"
    │           ├─ Ubicación: /data/user/0/com.example.pruebas_flutter/app_flutter/pruebas_flutter.db
    │           └─ Campos guardados:
    │               - id (PRIMARY KEY AUTOINCREMENT)
    │               - tableId (para agrupar por día)
    │               - number (número del racimo)
    │               - weightKg (peso en kg)
    │               - weighingTime (timestamp)
    │               - cintaColor (null al guardar)
    │               - cuadrilla (null al guardar)
    │               - lote (null al guardar)
    │               - recusado (false al guardar)
    │               - createdAt (timestamp)
    │               - firebaseId (null al guardar)
    │
    └─ PASO 2: GUARDAR EN FIREBASE (BACKGROUND) ☁️
        │
        └─ Cloud Firestore
            ├─ Colección: "bunch_entries"
            ├─ Documento: generado automáticamente
            └─ Campos: mismos que los de arriba
```

## 3️⃣ LECTURA DE DATOS - TABLA DE RACIMOS

**Ubicación:** `lib/presentation/pages/bunch_table_page.dart`

```
BunchTablePage (pagina de tabla de racimos)
    ↓
_BunchEntriesList (StatelessWidget)
    ↓
StreamBuilder<List<Map<String, dynamic>>>
    ↓
localStorage.streamBunchEntriesByTable(tableId)
    ├─ Lee desde: Base de datos SQLite local
    ├─ Frecuencia: Cada 300ms actualiza
    └─ Consulta WHERE: tableId = el ID de la tabla de hoy
        │
        ├─ Si encuentra racimos → muestra en ListView
        │
        └─ Si NO encuentra racimos → muestra "Sin racimos aún"
```

## 4️⃣ EDICIÓN DE CAMPOS

**Ubicación:** `_EditableFieldsRow` en `bunch_table_page.dart`

```
Usuario toca "Editar" en un racimo
    ↓
Se abre el formulario de edición
    ↓
Usuario edita: color, cuadrilla, lote, recusado
    ↓
Usuario toca "Guardar"
    ↓
localStorage.updateBunchEntry(
    localId: id,
    cintaColor: ...,
    cuadrilla: ...,
    lote: ...,
    recusado: ...
)
    └─ Actualiza SOLO la base de datos local
```

## 🐛 COMO DEPURAR SI NO VES DATOS

1. **Abre la tabla de racimos**
2. **Toca el icono 🐛 (DEBUG) en la esquina superior derecha**
3. **Mira los logs en la terminal Flutter**

Los logs mostrarán:
- `🐛 TableId buscado: KBgSHasqjzSebrepvPIq` ← ID que estamos buscando
- `🐛 Total de racimos en BD: 0 o N` ← Cuántos racimos hay en total
- `🐛   - ID local: X, TableId: Y, Número: Z, Peso: W` ← Detalles de cada uno

---

## ✅ FLUJO COMPLETO CORRECTO

```
✅ Presionar GUARDAR en Home
    ↓
✅ Guardar localmente (datos visibles al instante)
    ↓
✅ Guardar en Firebase (background)
    ↓
✅ Ir a tabla de racimos
    ↓
✅ Ver datos en la tabla (leyendo de SQLite local)
    ↓
✅ Editar campos en la tabla
    ↓
✅ Los datos editados se guardan localmente
```

---

## 📁 BASE DE DATOS LOCAL

- **Motor:** SQLite
- **Paquete:** sqflite
- **Tabla:** `bunch_entries`
- **Índices:** Creado en `tableId` para búsquedas rápidas
- **Sincronización:** Los datos se envían a Firebase pero se leen de SQLite local


# 🔥 Firebase - Guía de Uso Rápido

## ✅ Implementación Completada

Firebase ha sido completamente implementado en tu aplicación Flutter. Aquí está todo lo que se ha configurado:

### 📦 Dependencias Agregadas

```yaml
firebase_core: ^3.6.0        # Core de Firebase
cloud_firestore: ^5.4.4      # Base de datos Firestore
firebase_auth: ^5.3.1        # Autenticación (opcional)
```

### 📁 Archivos Creados

```
lib/
├── firebase_options.dart                                    # Configuración de Firebase
├── core/
│   └── firebase_provider.dart                              # Provider global
├── data/
│   └── firebase/
│       ├── firebase_service.dart                           # Servicio principal
│       └── firebase_models.dart                            # Modelos de datos
└── presentation/
    ├── blocs/
    │   └── persistence/
    │       └── measurement_persistence_cubit.dart          # Cubit para guardar mediciones
    └── widgets/
        └── firebase_widgets.dart                           # Widgets de UI
```

## 🚀 Configuración Necesaria

### **PASO OBLIGATORIO**: Ejecutar FlutterFire CLI

```bash
# 1. Instalar Firebase Tools
npm install -g firebase-tools

# 2. Instalar FlutterFire CLI
dart pub global activate flutterfire_cli

# 3. Configurar el proyecto (IMPORTANTE)
flutterfire configure
```

El comando `flutterfire configure` va a:
- 🔑 Autenticarte con tu cuenta de Google
- 📋 Mostrarte tus proyectos de Firebase
- ⚙️ Generar automáticamente las credenciales
- 📱 Configurar Android, iOS y otras plataformas

## 💾 Estructura de Datos en Firestore

### Colecciones

#### 1️⃣ **devices** - Dispositivos Bluetooth
```json
{
  "id": "DE:FD:76:A4:D7:ED",
  "name": "TRU-TEST S3",
  "lastSeen": "2025-11-14T10:30:00Z"
}
```

#### 2️⃣ **measurements** - Mediciones de Peso
```json
{
  "deviceId": "DE:FD:76:A4:D7:ED",
  "weight": 245.5,
  "unit": "kg",
  "sessionId": "abc123",
  "timestamp": "2025-11-14T10:30:15Z",
  "metadata": {
    "status": "WeightStatus.stable",
    "batteryPercent": 85.0,
    "batteryVoltage": 3.7
  }
}
```

#### 3️⃣ **sessions** - Sesiones de Medición
```json
{
  "deviceId": "DE:FD:76:A4:D7:ED",
  "animalId": "animal_001",
  "startTime": "2025-11-14T10:00:00Z",
  "endTime": "2025-11-14T11:00:00Z",
  "measurementCount": 25,
  "status": "completed",
  "metadata": {
    "finca": "La Esperanza",
    "operador": "Juan"
  }
}
```

## 🎯 Cómo Usar Firebase en Tu App

### Opción 1: Guardar Mediciones Manualmente

```dart
// En cualquier widget
final firebaseService = FirebaseProvider.of(context);

// Guardar una medición
await firebaseService.saveMeasurement(
  deviceId: 'DE:FD:76:A4:D7:ED',
  weight: 245.5,
  unit: 'kg',
  metadata: {'temperatura': 25.0},
);
```

### Opción 2: Usar el Cubit de Persistencia (Automático)

```dart
// 1. Agregar el cubit en main.dart
BlocProvider(
  create: (context) => MeasurementPersistenceCubit(
    FirebaseService(),
    context.read<ConnectionBloc>(),
  ),
)

// 2. Iniciar sesión cuando conectes a un dispositivo
context.read<MeasurementPersistenceCubit>().startSession(
  deviceId: device.id,
  animalId: 'animal_123',
);

// 3. Las mediciones se guardan automáticamente mientras pesas
// ...

// 4. Finalizar sesión cuando desconectes
context.read<MeasurementPersistenceCubit>().endSession();
```

### Opción 3: Mostrar Historial de Mediciones

```dart
// Usar el widget en cualquier página
MeasurementHistoryWidget(
  deviceId: 'DE:FD:76:A4:D7:ED',  // Opcional
  sessionId: 'session_123',        // Opcional
)
```

## 📊 Widgets Disponibles

### `MeasurementHistoryWidget`
Muestra el historial de mediciones en tiempo real.

```dart
MeasurementHistoryWidget(
  sessionId: sessionId,  // Filtrar por sesión
  deviceId: deviceId,    // Filtrar por dispositivo
)
```

### `SessionsWidget`
Muestra las sesiones de medición.

```dart
SessionsWidget(
  deviceId: deviceId,    // Opcional
)
```

## 🔧 Funciones del Servicio Firebase

```dart
final service = FirebaseService();

// Dispositivos
await service.saveDevice(device);
Stream<List<Map>> devices = service.getDevices();

// Mediciones
String id = await service.saveMeasurement(...);
await service.deleteMeasurement(id);
Stream<List<Map>> measurements = service.getMeasurements(...);

// Sesiones
String sessionId = await service.createSession(...);
await service.endSession(sessionId);
await service.deleteSession(sessionId);
Stream<List<Map>> sessions = service.getSessions(...);
```

## 🔒 Reglas de Seguridad (Firebase Console)

Para desarrollo, usa estas reglas en **Firestore > Reglas**:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;  // ⚠️ Solo para desarrollo
    }
  }
}
```

⚠️ **Para producción**, implementa reglas más restrictivas con autenticación.

## 🧪 Probar la Implementación

### 1. Ejecutar la App
```bash
flutter run
```

Deberías ver en los logs:
```
✅ Firebase inicializado correctamente
```

### 2. Verificar en Firebase Console

1. Ve a [Firebase Console](https://console.firebase.google.com/)
2. Abre tu proyecto
3. Ve a **Firestore Database**
4. Deberías ver las colecciones cuando uses la app

## 🎨 Ejemplo Completo de Integración

Agregar el cubit de persistencia a tu app:

```dart
// lib/main.dart
return FirebaseProvider(
  firebaseService: FirebaseService(),
  child: MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => ScanCubit(...)),
      BlocProvider(create: (_) => ConnectionBloc(...)),
      
      // Nuevo cubit de persistencia
      BlocProvider(
        create: (context) => MeasurementPersistenceCubit(
          FirebaseService(),
          context.read<ConnectionBloc>(),
        ),
      ),
    ],
    child: MaterialApp(...),
  ),
);
```

Luego, en tu página de conexión:

```dart
// Iniciar sesión al conectar
context.read<MeasurementPersistenceCubit>().startSession(
  deviceId: device.id,
);

// Finalizar sesión al desconectar
context.read<MeasurementPersistenceCubit>().endSession();
```

## 📱 Agregar Pantalla de Historial

Crea una nueva página:

```dart
class HistoryPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Historial')),
      body: Column(
        children: [
          // Tabs para sesiones y mediciones
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(tabs: [
                    Tab(text: 'Mediciones'),
                    Tab(text: 'Sesiones'),
                  ]),
                  Expanded(
                    child: TabBarView(
                      children: [
                        MeasurementHistoryWidget(),
                        SessionsWidget(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

## ❓ Solución de Problemas

### Error: "Firebase not initialized"
```bash
# Ejecutar configuración
flutterfire configure
```

### Error: "Missing google-services.json"
```bash
# Limpiar y regenerar
flutter clean
flutterfire configure
flutter pub get
```

### Error en iOS
```bash
cd ios
pod install
cd ..
flutter clean
flutter run
```

## 📚 Documentación Completa

Ver **FIREBASE_CONFIG.md** para documentación detallada.

## ✨ Próximos Pasos

1. ✅ Ejecutar `flutterfire configure`
2. ✅ Probar la app y ver si Firebase se inicializa
3. ✅ Verificar que las mediciones se guarden en Firestore
4. ⭐ Agregar el cubit de persistencia a tu app
5. ⭐ Crear una página de historial
6. ⭐ Implementar autenticación (opcional)

---

**🎉 ¡Firebase está listo para usar!** Solo falta ejecutar `flutterfire configure` para generar las credenciales.

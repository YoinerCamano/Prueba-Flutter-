# Configuración de Firebase

Este documento explica cómo configurar Firebase en la aplicación Flutter para almacenar datos de mediciones de básculas Bluetooth.

## 📋 Estructura Implementada

### Archivos Creados

1. **`lib/data/firebase/firebase_service.dart`**: Servicio principal para interactuar con Firestore
2. **`lib/data/firebase/firebase_models.dart`**: Modelos de datos para Firebase
3. **`lib/core/firebase_provider.dart`**: Provider para acceder al servicio en toda la app
4. **`lib/firebase_options.dart`**: Configuración de Firebase (requiere configuración)

### Colecciones en Firestore

La aplicación utiliza tres colecciones principales:

#### 1. `devices` - Dispositivos Bluetooth
```dart
{
  id: String,           // ID del dispositivo (MAC o UUID)
  name: String,         // Nombre del dispositivo
  lastSeen: Timestamp   // Última vez visto
}
```

#### 2. `measurements` - Mediciones de Peso
```dart
{
  deviceId: String,              // ID del dispositivo
  weight: double,                // Peso medido
  unit: String,                  // Unidad (kg, lb, etc.)
  sessionId: String?,            // ID de la sesión (opcional)
  timestamp: Timestamp,          // Fecha/hora de la medición
  metadata: Map<String, dynamic> // Metadatos adicionales
}
```

#### 3. `sessions` - Sesiones de Medición
```dart
{
  deviceId: String,              // ID del dispositivo
  animalId: String?,             // ID del animal (opcional)
  startTime: Timestamp,          // Inicio de la sesión
  endTime: Timestamp?,           // Fin de la sesión
  measurementCount: int,         // Contador de mediciones
  metadata: Map<String, dynamic>, // Metadatos adicionales
  status: String                 // 'active', 'completed', 'cancelled'
}
```

## 🚀 Configuración Inicial

### Paso 1: Crear Proyecto en Firebase

1. Ve a [Firebase Console](https://console.firebase.google.com/)
2. Crea un nuevo proyecto o selecciona uno existente
3. Habilita **Cloud Firestore** en la sección de base de datos
4. Configura las reglas de seguridad según tus necesidades

### Paso 2: Configurar FlutterFire CLI

Instala FlutterFire CLI (requiere Node.js):

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
```

### Paso 3: Inicializar Firebase en el Proyecto

Ejecuta en la raíz del proyecto:

```bash
flutterfire configure
```

Este comando:
- Te pedirá autenticación con tu cuenta de Google
- Listará tus proyectos de Firebase
- Generará automáticamente `firebase_options.dart` con las credenciales
- Configurará Android, iOS y otras plataformas

### Paso 4: Verificar Dependencias

Asegúrate de que el archivo `pubspec.yaml` tiene:

```yaml
dependencies:
  firebase_core: ^3.6.0
  cloud_firestore: ^5.4.4
  firebase_auth: ^5.3.1  # Opcional, para autenticación
```

Ejecuta:

```bash
flutter pub get
```

### Paso 5: Configuración de Android

Verifica que `android/app/build.gradle.kts` tenga:

```kotlin
android {
    compileSdk = 34
    
    defaultConfig {
        minSdk = 21  // Firebase requiere mínimo API 21
        targetSdk = 34
        // ...
    }
}
```

## 📱 Uso del Servicio Firebase

### Acceder al Servicio

```dart
// Desde cualquier widget
final firebaseService = FirebaseProvider.of(context);
```

### Ejemplos de Uso

#### Guardar un Dispositivo
```dart
await firebaseService.saveDevice(device);
```

#### Crear una Sesión
```dart
final sessionId = await firebaseService.createSession(
  deviceId: 'DE:FD:76:A4:D7:ED',
  animalId: 'animal_123',
  metadata: {'finca': 'La Esperanza'},
);
```

#### Guardar una Medición
```dart
await firebaseService.saveMeasurement(
  deviceId: 'DE:FD:76:A4:D7:ED',
  weight: 245.5,
  unit: 'kg',
  sessionId: sessionId,
  metadata: {'temperatura': 25.3},
);
```

#### Obtener Mediciones (Stream)
```dart
StreamBuilder<List<Map<String, dynamic>>>(
  stream: firebaseService.getMeasurements(sessionId: sessionId),
  builder: (context, snapshot) {
    if (!snapshot.hasData) return CircularProgressIndicator();
    final measurements = snapshot.data!;
    return ListView.builder(
      itemCount: measurements.length,
      itemBuilder: (context, index) {
        final m = measurements[index];
        return ListTile(
          title: Text('${m['weight']} ${m['unit']}'),
          subtitle: Text('${m['timestamp']}'),
        );
      },
    );
  },
)
```

#### Finalizar una Sesión
```dart
await firebaseService.endSession(sessionId);
```

## 🔒 Reglas de Seguridad Sugeridas

En Firebase Console > Firestore > Reglas, configura:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Permitir lectura/escritura a dispositivos
    match /devices/{deviceId} {
      allow read, write: if true; // Ajustar según autenticación
    }
    
    // Permitir lectura/escritura a mediciones
    match /measurements/{measurementId} {
      allow read, write: if true; // Ajustar según autenticación
    }
    
    // Permitir lectura/escritura a sesiones
    match /sessions/{sessionId} {
      allow read, write: if true; // Ajustar según autenticación
    }
  }
}
```

⚠️ **Importante**: Las reglas anteriores son para desarrollo. Para producción, implementa autenticación y reglas más restrictivas.

## 🧪 Pruebas

### Verificar Conexión

Después de ejecutar `flutterfire configure`, prueba la app:

```bash
flutter run
```

Deberías ver en los logs:
```
✅ Firebase inicializado correctamente
```

### Probar Escritura de Datos

Desde la consola de Firebase, ve a Firestore y verifica que se crean las colecciones cuando uses el servicio.

## 📊 Índices Recomendados

Para mejorar el rendimiento de las consultas, crea índices en Firestore:

1. **measurements**: `deviceId` (asc) + `timestamp` (desc)
2. **sessions**: `deviceId` (asc) + `startTime` (desc)
3. **sessions**: `status` (asc) + `startTime` (desc)

Firebase te sugerirá crear estos índices automáticamente cuando ejecutes las consultas por primera vez.

## 🔧 Solución de Problemas

### Error: "Firebase not initialized"
- Asegúrate de que `Firebase.initializeApp()` se ejecuta en `main()`
- Verifica que `firebase_options.dart` existe y tiene las credenciales correctas

### Error: "Missing google-services.json"
- Ejecuta `flutterfire configure` nuevamente
- Para Android manualmente: descarga `google-services.json` de Firebase Console y colócalo en `android/app/`

### Error en iOS: "Could not find Firebase.h"
- Ejecuta `cd ios && pod install && cd ..`
- Limpia el build: `flutter clean && flutter pub get`

### Reglas de Seguridad Bloqueando Acceso
- Verifica las reglas en Firebase Console > Firestore > Reglas
- Para desarrollo, usa reglas permisivas (pero nunca en producción)

## 📚 Recursos Adicionales

- [FlutterFire Documentation](https://firebase.flutter.dev/)
- [Firestore Documentation](https://firebase.google.com/docs/firestore)
- [Firebase Console](https://console.firebase.google.com/)

## ✅ Siguiente Paso

Ejecuta:

```bash
flutterfire configure
```

Y selecciona tu proyecto de Firebase para generar automáticamente las configuraciones necesarias.

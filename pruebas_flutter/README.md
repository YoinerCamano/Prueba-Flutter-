# pruebas_flutter

Aplicación Flutter para comunicación con básculas Bluetooth (SPP y BLE) con persistencia en Firebase.

## 🎯 Características

- ✅ Conexión Bluetooth (SPP y BLE)
- ✅ Soporte para Tru-Test S3 y otras básculas
- ✅ Lectura de peso en tiempo real
- ✅ Persistencia de datos con Firebase Firestore
- ✅ Auto-guardado de mediciones
- ✅ Gestión de sesiones de pesaje
- ✅ Historial de mediciones

## 🚀 Configuración Rápida

### 1. Instalar Dependencias

```bash
flutter pub get
```

### 2. Configurar Firebase

```bash
# Instalar herramientas (solo una vez)
npm install -g firebase-tools
dart pub global activate flutterfire_cli

# Configurar proyecto
flutterfire configure
```

Ver **[QUICK_FIREBASE_SETUP.md](QUICK_FIREBASE_SETUP.md)** para más detalles.

### 3. Ejecutar la App

```bash
flutter run
```

## 📚 Documentación

- **[QUICK_FIREBASE_SETUP.md](QUICK_FIREBASE_SETUP.md)** - Guía rápida de configuración
- **[FIREBASE_SETUP.md](FIREBASE_SETUP.md)** - Guía completa de uso
- **[FIREBASE_CONFIG.md](FIREBASE_CONFIG.md)** - Documentación técnica
- **[FIREBASE_IMPLEMENTATION_SUMMARY.md](FIREBASE_IMPLEMENTATION_SUMMARY.md)** - Resumen de implementación

## 🔥 Funcionalidades de Firebase

### Auto-guardado de Mediciones
```dart
// Iniciar sesión de pesaje
context.read<MeasurementPersistenceCubit>().startSession(
  deviceId: device.id,
  animalId: 'animal_123',
);

// Las mediciones se guardan automáticamente

// Finalizar sesión
context.read<MeasurementPersistenceCubit>().endSession();
```

### Ver Historial
```dart
// Widget con stream en tiempo real
MeasurementHistoryWidget(
  deviceId: 'DE:FD:76:A4:D7:ED',
  sessionId: sessionId,
)
```

## 📱 Estructura del Proyecto

```
lib/
├── main.dart
├── firebase_options.dart
├── core/
│   ├── firebase_provider.dart
│   ├── exceptions.dart
│   ├── failures.dart
│   └── result.dart
├── data/
│   ├── firebase/
│   │   ├── firebase_service.dart
│   │   └── firebase_models.dart
│   ├── bluetooth_repository_spp.dart
│   ├── ble/
│   └── datasources/
├── domain/
│   ├── bluetooth_repository.dart
│   └── entities.dart
└── presentation/
    ├── blocs/
    │   ├── connection/
    │   ├── scan/
    │   └── persistence/
    ├── pages/
    │   ├── home_page.dart
    │   └── weighing_with_firebase_page.dart
    └── widgets/
        └── firebase_widgets.dart
```

## 🛠️ Tecnologías

- Flutter SDK >=3.4.0
- Firebase Core 3.6.0
- Cloud Firestore 5.4.4
- Flutter BLoC 8.1.4
- Bluetooth (SPP y BLE)

## 📊 Colecciones Firestore

- **devices** - Dispositivos Bluetooth
- **measurements** - Mediciones de peso
- **sessions** - Sesiones de pesaje

## Getting Started

This project is a starting point for a Flutter application with Bluetooth connectivity and Firebase integration.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


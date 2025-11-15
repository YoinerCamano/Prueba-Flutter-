# 🔧 Configuración Manual de Firebase (Solución al Error)

## ❌ Error Encontrado

El comando `flutterfire configure` falló porque no tienes proyectos de Firebase creados.

## ✅ Solución: Configuración Manual (5 minutos)

### Paso 1: Crear Proyecto en Firebase Console

1. Ve a [Firebase Console](https://console.firebase.google.com/)
2. Haz clic en **"Agregar proyecto"** o **"Add project"**
3. Nombre del proyecto: `pruebas-flutter` (o el que prefieras)
4. **Desactiva** Google Analytics (no es necesario para empezar)
5. Haz clic en **"Crear proyecto"**

### Paso 2: Habilitar Firestore

1. En el menú lateral, haz clic en **"Firestore Database"**
2. Haz clic en **"Crear base de datos"**
3. Selecciona **"Modo de prueba"** (para desarrollo)
4. Elige la ubicación más cercana (por ejemplo: `southamerica-east1`)
5. Haz clic en **"Habilitar"**

### Paso 3: Agregar App Android

1. En la página principal del proyecto, haz clic en el ícono de **Android**
2. **Nombre del paquete Android**: `com.example.pruebas_flutter`
   
   > ⚠️ **IMPORTANTE**: Este debe coincidir con el de tu `android/app/build.gradle.kts`

3. **Nombre de la app** (opcional): `Pruebas Flutter`
4. Haz clic en **"Registrar app"**
5. **Descarga** el archivo `google-services.json`
6. **Guarda** el archivo en: `android/app/google-services.json`
7. Sigue los pasos de configuración (o sáltate, ya está configurado)
8. Haz clic en **"Continuar a la consola"**

### Paso 4: Obtener Credenciales para flutter_options.dart

1. En Firebase Console, ve a **Configuración del proyecto** (ícono de engranaje)
2. En la pestaña **"General"**, baja hasta **"Tus apps"**
3. Haz clic en tu app Android
4. Verás los siguientes datos:

```
API Key: AIza...
App ID: 1:123...:android:abc...
Project ID: pruebas-flutter
Messaging Sender ID: 123456789
```

### Paso 5: Actualizar firebase_options.dart

Abre `lib/firebase_options.dart` y reemplaza los valores `YOUR_...` con tus credenciales:

```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'TU_API_KEY_AQUI',              // De Firebase Console
  appId: 'TU_APP_ID_AQUI',                // De Firebase Console
  messagingSenderId: 'TU_SENDER_ID_AQUI', // De Firebase Console
  projectId: 'pruebas-flutter',           // Nombre de tu proyecto
  storageBucket: 'pruebas-flutter.appspot.com',
);
```

### Paso 6: Verificar android/app/build.gradle.kts

Asegúrate de que el archivo tenga estas configuraciones:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") version "4.4.0" apply false  // Esta línea
}

android {
    namespace = "com.example.pruebas_flutter"  // Debe coincidir con Firebase
    compileSdk = 34
    
    defaultConfig {
        applicationId = "com.example.pruebas_flutter"  // Debe coincidir con Firebase
        minSdk = 21  // Firebase requiere mínimo 21
        targetSdk = 34
        versionCode = 2
        versionName = "1.1.0"
    }
}

// Al final del archivo
apply(plugin = "com.google.gms.google-services")
```

### Paso 7: Verificar android/build.gradle.kts

```kotlin
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.1.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
    id("com.google.gms.google-services") version "4.4.0" apply false  // Esta línea
}
```

### Paso 8: Probar la Configuración

```powershell
# Limpiar el proyecto
flutter clean

# Obtener dependencias
flutter pub get

# Ejecutar la app
flutter run
```

Deberías ver en los logs:
```
✅ Firebase inicializado correctamente
```

## 🎯 Configuración Rápida (Copy-Paste)

Si quieres ir más rápido, aquí está todo lo que necesitas:

### 1. Verificar el Package Name

```powershell
# En android/app/build.gradle.kts busca:
# applicationId = "com.example.pruebas_flutter"
```

### 2. Descargar google-services.json

- Ve a Firebase Console > Tu Proyecto > Configuración > Tus Apps
- Descarga `google-services.json`
- Colócalo en `android/app/google-services.json`

### 3. Copiar Credenciales

De Firebase Console, copia:
- API Key
- App ID
- Project ID
- Messaging Sender ID

### 4. Actualizar firebase_options.dart

Reemplaza en `lib/firebase_options.dart`:

```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'AIza...',                    // De Firebase
  appId: '1:123...:android:abc...',     // De Firebase
  messagingSenderId: '123456789',       // De Firebase
  projectId: 'tu-proyecto-id',          // De Firebase
  storageBucket: 'tu-proyecto-id.appspot.com',
);
```

## ❓ Solución de Problemas

### "google-services.json not found"

```powershell
# Verifica que el archivo existe
Test-Path android/app/google-services.json
```

Si no existe, descárgalo nuevamente de Firebase Console.

### "Package name doesn't match"

El `applicationId` en `android/app/build.gradle.kts` debe ser EXACTAMENTE el mismo que registraste en Firebase.

### "Firebase not initialized"

Verifica que `firebase_options.dart` tenga las credenciales correctas (no `YOUR_...`).

## 📝 Checklist Final

- [ ] Proyecto creado en Firebase Console
- [ ] Firestore habilitado
- [ ] App Android registrada en Firebase
- [ ] `google-services.json` descargado y colocado en `android/app/`
- [ ] `firebase_options.dart` actualizado con credenciales reales
- [ ] `android/build.gradle.kts` con plugin de Google Services
- [ ] `android/app/build.gradle.kts` con plugin aplicado
- [ ] Ejecutado `flutter clean && flutter pub get`
- [ ] App ejecutada con `flutter run`

## 🎉 ¡Listo!

Una vez completados estos pasos, Firebase estará funcionando completamente en tu app.

---

**Tiempo estimado**: 5-10 minutos
**Dificultad**: Fácil ⭐

Si tienes problemas, verifica que el `applicationId` en Android coincida con el paquete registrado en Firebase.

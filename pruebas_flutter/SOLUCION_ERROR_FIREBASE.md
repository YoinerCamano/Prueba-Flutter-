# ✅ Solución al Error de Firebase - Pasos a Seguir

## 🔧 Ya Configuré Automáticamente:

✅ Plugin de Google Services agregado a `android/settings.gradle.kts`
✅ Plugin de Google Services agregado a `android/app/build.gradle.kts`  
✅ minSdk configurado a 21 (requerido por Firebase)

## 📝 Pasos que DEBES Hacer (en orden):

### 1️⃣ Crear Proyecto en Firebase Console (2 minutos)

Abre: https://console.firebase.google.com/

1. Haz clic en **"Agregar proyecto"**
2. Nombre: `pruebas-flutter`
3. **Desactiva** Google Analytics
4. Haz clic en **"Crear proyecto"**

### 2️⃣ Habilitar Firestore (1 minuto)

1. En el menú lateral → **"Firestore Database"**
2. **"Crear base de datos"**
3. Selecciona **"Modo de prueba"**
4. Ubicación: `southamerica-east1` (o la más cercana)
5. **"Habilitar"**

### 3️⃣ Registrar App Android (3 minutos)

1. En la página principal, haz clic en el ícono de **Android** (robot verde)
2. **Nombre del paquete**: `com.example.pruebas_flutter`
   
   ⚠️ **DEBE SER EXACTAMENTE**: `com.example.pruebas_flutter`

3. Haz clic en **"Registrar app"**
4. **DESCARGA** el archivo `google-services.json`
5. **GUARDA** el archivo en: `android/app/google-services.json`

   ```
   📁 pruebas_flutter/
   └── 📁 android/
       └── 📁 app/
           └── 📄 google-services.json  ← Aquí
   ```

6. Haz clic en **"Siguiente"** → **"Siguiente"** → **"Continuar a la consola"**

### 4️⃣ Copiar Credenciales (2 minutos)

1. En Firebase Console → **⚙️ Configuración del proyecto**
2. Baja hasta **"Tus apps"**
3. Verás algo como esto:

```
ID de la aplicación: 1:123456789:android:abc123def456
Clave de API: AIzaSyABC123...XYZ789
ID del proyecto: pruebas-flutter
ID del emisor: 123456789
```

4. **COPIA** estos valores

### 5️⃣ Actualizar firebase_options.dart (1 minuto)

Abre: `lib/firebase_options.dart`

Busca la sección `android` y reemplaza con TUS valores:

```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'AIzaSy...',              // TU Clave de API
  appId: '1:123...:android:abc...',  // TU ID de la aplicación
  messagingSenderId: '123456789',    // TU ID del emisor
  projectId: 'pruebas-flutter',      // TU ID del proyecto
  storageBucket: 'pruebas-flutter.appspot.com',  // TU proyecto.appspot.com
);
```

### 6️⃣ Probar (1 minuto)

```powershell
flutter clean
flutter pub get
flutter run
```

Deberías ver:
```
✅ Firebase inicializado correctamente
```

## 📋 Checklist

Marca cuando completes cada paso:

- [ ] Proyecto creado en Firebase Console
- [ ] Firestore habilitado en modo prueba
- [ ] App Android registrada con `com.example.pruebas_flutter`
- [ ] Archivo `google-services.json` descargado
- [ ] Archivo `google-services.json` en `android/app/google-services.json`
- [ ] Credenciales copiadas de Firebase Console
- [ ] `firebase_options.dart` actualizado con credenciales reales
- [ ] Ejecutado `flutter clean && flutter pub get`
- [ ] App corriendo con `flutter run`
- [ ] Log muestra "✅ Firebase inicializado correctamente"

## ❓ Si Algo Sale Mal

### Error: "google-services.json not found"

Verifica que el archivo esté en la ruta correcta:

```powershell
Test-Path android/app/google-services.json
```

Si devuelve `False`, descárgalo de nuevo desde Firebase Console.

### Error: "Package name mismatch"

El `applicationId` en tu proyecto es: `com.example.pruebas_flutter`

DEBE ser EXACTAMENTE el mismo en Firebase Console.

### Error: "Firebase not initialized"

Verifica que `firebase_options.dart` tenga las credenciales reales (no `YOUR_...`).

## 🎯 Tiempo Total Estimado: 10 minutos

## 📚 Documentación Adicional

- **FIREBASE_MANUAL_SETUP.md** - Guía detallada completa
- **FIREBASE_SETUP.md** - Guía de uso de Firebase
- **FIREBASE_CONFIG.md** - Documentación técnica

---

**💡 Consejo**: Haz todos los pasos en orden. No te saltes ninguno.

**🎉 Una vez completado, Firebase estará funcionando en tu app!**

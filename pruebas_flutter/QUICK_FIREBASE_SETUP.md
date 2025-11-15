# 🚀 Configuración Rápida de Firebase

## ⚡ Comandos para Ejecutar (en orden)

### 1️⃣ Instalar Firebase Tools
```powershell
npm install -g firebase-tools
```

### 2️⃣ Instalar FlutterFire CLI
```powershell
dart pub global activate flutterfire_cli
```

### 3️⃣ Configurar Firebase (IMPORTANTE)
```powershell
flutterfire configure
```

Este comando te va a pedir:
- ✅ Login con tu cuenta de Google
- ✅ Seleccionar o crear un proyecto de Firebase
- ✅ Seleccionar las plataformas (Android, iOS, etc.)
- ✅ Generar automáticamente `firebase_options.dart` con tus credenciales

### 4️⃣ Verificar que funciona
```powershell
flutter run
```

Deberías ver en los logs:
```
✅ Firebase inicializado correctamente
```

## 🔥 ¿Qué hace `flutterfire configure`?

1. **Autentica** con tu cuenta de Google
2. **Lista** tus proyectos de Firebase (o crea uno nuevo)
3. **Configura** Android, iOS, Web automáticamente
4. **Genera** `lib/firebase_options.dart` con tus credenciales
5. **Descarga** archivos de configuración necesarios:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`

## ✅ Verificación

Después de ejecutar `flutterfire configure`, verifica que existan:

- ✅ `lib/firebase_options.dart` (con tus credenciales)
- ✅ `android/app/google-services.json` (para Android)
- ✅ `ios/Runner/GoogleService-Info.plist` (para iOS)

## 🎯 Próximo Paso

Una vez configurado, puedes empezar a usar Firebase:

```dart
// Las mediciones se guardan automáticamente si usas el cubit
context.read<MeasurementPersistenceCubit>().startSession(
  deviceId: device.id,
);
```

## 📚 Más Información

- Ver **FIREBASE_SETUP.md** para guía completa
- Ver **FIREBASE_CONFIG.md** para documentación técnica
- Ver **FIREBASE_IMPLEMENTATION_SUMMARY.md** para resumen

## ❓ Problemas Comunes

### Error: "command not found: flutterfire"
```powershell
# Agregar dart pub global al PATH
# O ejecutar:
flutter pub global run flutterfire_cli:flutterfire configure
```

### Error: "Firebase not initialized"
```powershell
# Ejecutar configuración nuevamente
flutterfire configure
```

### Error en Android
```powershell
# Verificar que existe google-services.json
ls android/app/google-services.json
```

### Error en iOS
```powershell
cd ios
pod install
cd ..
```

---

**🎉 ¡Listo! Con estos 3 comandos Firebase estará completamente configurado.**

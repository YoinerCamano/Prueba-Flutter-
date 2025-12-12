# Guía de Configuración

## Requisitos
- Flutter 3.x
- JDK 21 (Java LTS)
- Android SDK (API 21+)
- Firebase proyecto configurado

## Pasos
1. Instalar dependencias
```bash
flutter pub get
```
2. Configurar Firebase
```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
flutterfire configure
```
3. Android
- Copiar `google-services.json` a `android/app/`
- Verificar `android/app/build.gradle.kts` usa `JavaVersion.VERSION_21` y `kotlinOptions.jvmTarget = "21"`
4. Permisos Android 12+
- Revisar `_ensurePermissions()` en `lib/main.dart`
- Permisos: `bluetoothConnect`, `bluetoothScan`, `bluetooth`, `location`
5. Ejecutar
```bash
flutter run
```

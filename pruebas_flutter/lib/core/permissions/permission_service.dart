import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
/// Una clase de servicio que maneja los permisos de la aplicación.
/// 
/// Esta clase proporciona métodos para solicitar, verificar y gestionar varios
/// permisos del dispositivo como cámara, ubicación, almacenamiento, etc.
/// Actúa como un punto centralizado para todas las operaciones relacionadas
/// con permisos en la aplicación.


class PermissionService {
  Future<bool> ensureBlePermissions() async {
    if (Platform.isAndroid) {
      // Android 12+ permisos de Bluetooth dedicados
      final scan = await Permission.bluetoothScan.request();
      final connect = await Permission.bluetoothConnect.request();
      // Opcional advertise
      // final advertise = await Permission.bluetoothAdvertise.request();

      // Compat pre-12: algunos OEMs requieren localización para scan
      final location = await Permission.locationWhenInUse.request();

      return scan.isGranted && connect.isGranted && (location.isGranted || await _isAtLeastS());
    } else if (Platform.isIOS) {
      final bluetooth = await Permission.bluetooth.request();
      // Algunos iOS piden ubicación en uso para escaneo de proximidad
      final location = await Permission.locationWhenInUse.request();
      return bluetooth.isGranted && (location.isGranted || true);
    }
    return false;
  }

  Future<bool> _isAtLeastS() async {
    // No indispensable: solo para lógica condicional si quisieras.
    return true;
  }

  Future<bool> openAppSettingsIfDenied() async {
    return openAppSettings();
  }
}
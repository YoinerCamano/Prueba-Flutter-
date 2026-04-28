import 'package:connectivity_plus/connectivity_plus.dart';

/// Tipo de conexión actual.
enum NetworkType { none, wifi, mobile, other }

/// Servicio que verifica el tipo y disponibilidad de conexión a internet.
class ConnectivityService {
  final Connectivity _connectivity;

  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  /// Retorna el tipo de red actual.
  Future<NetworkType> currentNetworkType() async {
    final results = await _connectivity.checkConnectivity();
    return _fromResults(results);
  }

  /// Retorna true si hay conexión (cualquier tipo).
  Future<bool> hasConnection() async {
    final type = await currentNetworkType();
    return type != NetworkType.none;
  }

  /// Retorna true si la conexión es WiFi.
  Future<bool> isWifi() async {
    final type = await currentNetworkType();
    return type == NetworkType.wifi;
  }

  /// Stream de cambios de conectividad.
  Stream<NetworkType> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged.map(_fromResults);

  NetworkType _fromResults(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) return NetworkType.wifi;
    if (results.contains(ConnectivityResult.mobile)) return NetworkType.mobile;
    if (results.contains(ConnectivityResult.ethernet)) return NetworkType.wifi;
    if (results.any((r) =>
        r != ConnectivityResult.none && r != ConnectivityResult.bluetooth)) {
      return NetworkType.other;
    }
    return NetworkType.none;
  }
}

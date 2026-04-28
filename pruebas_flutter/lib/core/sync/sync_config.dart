import 'package:shared_preferences/shared_preferences.dart';

/// Opciones de intervalo de sincronización automática.
enum SyncInterval {
  min15(15, '15 minutos'),
  min30(30, '30 minutos'),
  hour1(60, '1 hora'),
  hour2(120, '2 horas'),
  hour4(240, '4 horas');

  const SyncInterval(this.minutes, this.label);
  final int minutes;
  final String label;

  Duration get duration => Duration(minutes: minutes);

  static SyncInterval fromMinutes(int minutes) {
    return SyncInterval.values.firstWhere(
      (e) => e.minutes == minutes,
      orElse: () => SyncInterval.hour2,
    );
  }
}

/// Modelo inmutable con la configuración de sincronización.
class SyncConfig {
  final bool autoSyncEnabled;
  final SyncInterval interval;
  final bool wifiOnly;

  const SyncConfig({
    this.autoSyncEnabled = false,
    this.interval = SyncInterval.hour2,
    this.wifiOnly = false,
  });

  SyncConfig copyWith({
    bool? autoSyncEnabled,
    SyncInterval? interval,
    bool? wifiOnly,
  }) {
    return SyncConfig(
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      interval: interval ?? this.interval,
      wifiOnly: wifiOnly ?? this.wifiOnly,
    );
  }
}

/// Servicio de persistencia de configuración de sincronización.
class SyncConfigRepository {
  static const String _keyAutoSync = 'sync_auto_enabled';
  static const String _keyInterval = 'sync_interval_minutes';
  static const String _keyWifiOnly = 'sync_wifi_only';
  static const String _keyApiBaseUrl = 'sync_api_base_url';
  static const String _keyApiEndpoint = 'sync_api_endpoint';
  static const String _keyApiToken = 'sync_api_token';
  static const String _keyLastSuccessfulSyncAt = 'sync_last_success_at';
  static const String _legacyDefaultEndpoint = '/api/sync/pesajes';
  static const String _defaultEndpoint = '/sync/pesajes';

  Future<SyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final autoSync = prefs.getBool(_keyAutoSync) ?? false;
    final intervalMinutes = prefs.getInt(_keyInterval) ?? SyncInterval.hour2.minutes;
    final wifiOnly = prefs.getBool(_keyWifiOnly) ?? false;
    return SyncConfig(
      autoSyncEnabled: autoSync,
      interval: SyncInterval.fromMinutes(intervalMinutes),
      wifiOnly: wifiOnly,
    );
  }

  Future<void> save(SyncConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSync, config.autoSyncEnabled);
    await prefs.setInt(_keyInterval, config.interval.minutes);
    await prefs.setBool(_keyWifiOnly, config.wifiOnly);
  }

  Future<ApiSyncConfig> loadApiConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl =
      prefs.getString(_keyApiBaseUrl) ?? 'http://192.168.0.49:8000';
    String endpoint = prefs.getString(_keyApiEndpoint) ?? _defaultEndpoint;
    // Migra automáticamente el endpoint anterior al nuevo requerido.
    if (endpoint.trim() == _legacyDefaultEndpoint) {
      endpoint = _defaultEndpoint;
      await prefs.setString(_keyApiEndpoint, endpoint);
    }
    final token = prefs.getString(_keyApiToken) ?? '';
    return ApiSyncConfig(
      baseUrl: baseUrl,
      endpoint: endpoint,
      token: token,
    );
  }

  Future<void> saveApiConfig(ApiSyncConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiBaseUrl, config.baseUrl);
    await prefs.setString(_keyApiEndpoint, config.endpoint);
    await prefs.setString(_keyApiToken, config.token);
  }

  Future<DateTime?> loadLastSuccessfulSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLastSuccessfulSyncAt);
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> saveLastSuccessfulSyncAt(DateTime dateTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSuccessfulSyncAt, dateTime.toIso8601String());
  }
}

/// Configuración de conexión al API de sincronización.
class ApiSyncConfig {
  final String baseUrl;
  final String endpoint;
  final String token;

  const ApiSyncConfig({
    this.baseUrl = 'http://192.168.0.49:8000',
    this.endpoint = '/sync/pesajes',
    this.token = '',
  });

  ApiSyncConfig copyWith({
    String? baseUrl,
    String? endpoint,
    String? token,
  }) {
    return ApiSyncConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      endpoint: endpoint ?? this.endpoint,
      token: token ?? this.token,
    );
  }

  bool get isComplete =>
      baseUrl.trim().isNotEmpty && endpoint.trim().isNotEmpty;

  Uri? buildUri() {
    if (!isComplete) return null;
    final normalizedBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final normalizedEndpoint = endpoint.trim().startsWith('/')
        ? endpoint.trim()
        : '/${endpoint.trim()}';
    return Uri.tryParse('$normalizedBase$normalizedEndpoint');
  }
}

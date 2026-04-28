import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_config.dart';
import 'sync_service.dart';

/// Adaptador HTTP para subir registros pendientes a un backend REST.
class ApiSyncUploadAdapter implements SyncUploadAdapter {
  final SyncConfigRepository _configRepository;
  final http.Client _client;

  ApiSyncUploadAdapter({
    SyncConfigRepository? configRepository,
    http.Client? client,
  })  : _configRepository = configRepository ?? SyncConfigRepository(),
        _client = client ?? http.Client();

  static const String _defaultDeviceId = 'bascula_01';
  static const String _appVersion = '1.0.0';

  @override
  Future<List<int>> upload(List<Map<String, dynamic>> records) async {
    final apiConfig = await _configRepository.loadApiConfig();
    final uri = apiConfig.buildUri();

    if (uri == null) {
      throw StateError(
        'Configura la API de sincronización antes de continuar',
      );
    }

    final payload = {
      'device_id': _defaultDeviceId,
      'app_version': _appVersion,
      'synced_at': DateTime.now().toIso8601String(),
      'pesajes': records.map(_mapRecord).toList(),
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    final response = await _client
        .post(uri, headers: headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Error HTTP ${response.statusCode}: ${response.body}',
      );
    }

    return records.map((r) => r['id_pesaje'] as int).toList();
  }

  Map<String, dynamic> _mapRecord(Map<String, dynamic> row) {
    final idPesaje = row['id_pesaje'];
    final uuid = (row['uuid'] as String?)?.trim();
    return {
      'uuid': (uuid != null && uuid.isNotEmpty) ? uuid : 'pesaje-$idPesaje',
      'id_viaje_local': row['id_viaje'],
      'numero_racimo': row['numero_racimo'],
      'peso': row['peso'],
      'color_cinta': row['color_cinta'],
      'fecha_pesaje': row['fecha_hora'],
    };
  }
}

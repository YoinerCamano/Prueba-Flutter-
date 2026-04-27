import '../../domain/entities.dart';
import '../local/database_service.dart';

class PesajeLocalDataSource {
  final DatabaseService databaseService;

  const PesajeLocalDataSource(this.databaseService);

  Future<ViajePesaje> crearViaje({
    required int idCuadrilla,
    required int idBascula,
    required String colorCinta,
    required String lote,
    String? observacion,
    DateTime? fechaInicio,
  }) async {
    final id = await databaseService.crearViajePesaje(
      idCuadrilla: idCuadrilla,
      idBascula: idBascula,
      colorCinta: colorCinta,
      lote: lote,
      observacion: observacion,
      fechaInicio: fechaInicio,
    );

    final active = await databaseService.obtenerViajeActivoPorBascula(idBascula);
    if (active == null || active['id_viaje'] != id) {
      throw StateError('No se pudo recuperar el viaje creado');
    }
    return ViajePesaje.fromMap(active);
  }

  Future<ViajePesaje?> obtenerViajeActivo({required int idBascula}) async {
    final map = await databaseService.obtenerViajeActivoPorBascula(idBascula);
    return map == null ? null : ViajePesaje.fromMap(map);
  }

  Future<int> obtenerSiguienteNumeroRacimo({required int idViaje}) async {
    final db = await databaseService.database;
    return databaseService.obtenerSiguienteNumeroRacimo(
      executor: db,
      idViaje: idViaje,
    );
  }

  Future<int> guardarPesajeEnViaje({
    required int idCuadrilla,
    required int idOperario,
    required int idBascula,
    required double peso,
    required String unidad,
    required DateTime fechaHora,
    String? colorCinta,
    String? lote,
    bool recusado = false,
    String? descripcionRecusado,
  }) {
    return databaseService.insertPesaje(
      idCuadrilla: idCuadrilla,
      idOperario: idOperario,
      idBascula: idBascula,
      peso: peso,
      unidad: unidad,
      fechaHora: fechaHora,
      colorCinta: colorCinta,
      lote: lote,
      recusado: recusado,
      recusadoDesc: descripcionRecusado,
    );
  }

  Future<void> finalizarViaje({
    required int idViaje,
    DateTime? fechaFin,
  }) {
    return databaseService.finalizarViajePesaje(
      idViaje: idViaje,
      fechaFin: fechaFin,
    );
  }
}

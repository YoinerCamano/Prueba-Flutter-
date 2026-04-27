import '../entities.dart';

abstract class PesajeRepository {
  Future<ViajePesaje> crearViaje({
    required int idCuadrilla,
    required int idBascula,
    required String colorCinta,
    required String lote,
    String? observacion,
    DateTime? fechaInicio,
  });

  Future<ViajePesaje?> obtenerViajeActivo({
    required int idBascula,
  });

  Future<int> obtenerSiguienteNumeroRacimo({
    required int idViaje,
  });

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
  });

  Future<void> finalizarViaje({
    required int idViaje,
    DateTime? fechaFin,
  });
}

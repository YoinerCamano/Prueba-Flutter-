import '../../domain/entities.dart';
import '../../domain/repositories/pesaje_repository.dart';
import '../datasources/pesaje_local_datasource.dart';

class PesajeRepositoryImpl implements PesajeRepository {
  final PesajeLocalDataSource local;

  const PesajeRepositoryImpl(this.local);

  @override
  Future<ViajePesaje> crearViaje({
    required int idCuadrilla,
    required int idBascula,
    required String colorCinta,
    required String lote,
    String? observacion,
    DateTime? fechaInicio,
  }) {
    return local.crearViaje(
      idCuadrilla: idCuadrilla,
      idBascula: idBascula,
      colorCinta: colorCinta,
      lote: lote,
      observacion: observacion,
      fechaInicio: fechaInicio,
    );
  }

  @override
  Future<ViajePesaje?> obtenerViajeActivo({required int idBascula}) {
    return local.obtenerViajeActivo(idBascula: idBascula);
  }

  @override
  Future<int> obtenerSiguienteNumeroRacimo({required int idViaje}) {
    return local.obtenerSiguienteNumeroRacimo(idViaje: idViaje);
  }

  @override
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
    return local.guardarPesajeEnViaje(
      idCuadrilla: idCuadrilla,
      idOperario: idOperario,
      idBascula: idBascula,
      peso: peso,
      unidad: unidad,
      fechaHora: fechaHora,
      colorCinta: colorCinta,
      lote: lote,
      recusado: recusado,
      descripcionRecusado: descripcionRecusado,
    );
  }

  @override
  Future<void> finalizarViaje({required int idViaje, DateTime? fechaFin}) {
    return local.finalizarViaje(idViaje: idViaje, fechaFin: fechaFin);
  }
}

import '../entities.dart';
import '../repositories/pesaje_repository.dart';

class CrearViajePesaje {
  final PesajeRepository repository;

  const CrearViajePesaje(this.repository);

  Future<ViajePesaje> call({
    required int idCuadrilla,
    required int idBascula,
    required String colorCinta,
    required String lote,
    String? observacion,
    DateTime? fechaInicio,
  }) {
    return repository.crearViaje(
      idCuadrilla: idCuadrilla,
      idBascula: idBascula,
      colorCinta: colorCinta,
      lote: lote,
      observacion: observacion,
      fechaInicio: fechaInicio,
    );
  }
}

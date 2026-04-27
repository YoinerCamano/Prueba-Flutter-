import '../repositories/pesaje_repository.dart';

class GuardarPesajeEnViaje {
  final PesajeRepository repository;

  const GuardarPesajeEnViaje(this.repository);

  Future<int> call({
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
    return repository.guardarPesajeEnViaje(
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
}

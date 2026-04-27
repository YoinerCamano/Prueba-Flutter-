import '../repositories/pesaje_repository.dart';

class FinalizarViajePesaje {
  final PesajeRepository repository;

  const FinalizarViajePesaje(this.repository);

  Future<void> call({required int idViaje, DateTime? fechaFin}) {
    return repository.finalizarViaje(idViaje: idViaje, fechaFin: fechaFin);
  }
}

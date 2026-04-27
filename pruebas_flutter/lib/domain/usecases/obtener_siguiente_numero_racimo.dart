import '../repositories/pesaje_repository.dart';

class ObtenerSiguienteNumeroRacimo {
  final PesajeRepository repository;

  const ObtenerSiguienteNumeroRacimo(this.repository);

  Future<int> call({required int idViaje}) {
    return repository.obtenerSiguienteNumeroRacimo(idViaje: idViaje);
  }
}

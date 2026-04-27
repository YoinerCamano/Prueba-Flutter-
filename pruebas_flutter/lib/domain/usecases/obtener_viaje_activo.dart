import '../entities.dart';
import '../repositories/pesaje_repository.dart';

class ObtenerViajeActivo {
  final PesajeRepository repository;

  const ObtenerViajeActivo(this.repository);

  Future<ViajePesaje?> call({required int idBascula}) {
    return repository.obtenerViajeActivo(idBascula: idBascula);
  }
}

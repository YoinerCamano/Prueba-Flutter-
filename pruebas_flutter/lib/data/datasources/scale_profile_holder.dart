import '../../domain/entities.dart';
import 'scale_model_registry.dart';

/// Guarda el perfil/modelo activo de la báscula para compartirlo entre BLoCs.
class ScaleProfileHolder {
  ScaleDescriptor _current;

  ScaleProfileHolder(ScaleDescriptor initial) : _current = initial;

  ScaleDescriptor get current => _current;

  void update(ScaleDescriptor descriptor) {
    _current = descriptor;
  }
}

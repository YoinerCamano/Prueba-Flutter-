import 'package:flutter/material.dart';
import '../data/firebase/firebase_service.dart';

/// Provider para acceder al servicio de Firebase en toda la aplicación
class FirebaseProvider extends InheritedWidget {
  final FirebaseService firebaseService;

  const FirebaseProvider({
    super.key,
    required this.firebaseService,
    required super.child,
  });

  static FirebaseService of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<FirebaseProvider>();
    if (provider == null) {
      throw Exception('FirebaseProvider not found in context');
    }
    return provider.firebaseService;
  }

  @override
  bool updateShouldNotify(FirebaseProvider oldWidget) {
    return firebaseService != oldWidget.firebaseService;
  }
}

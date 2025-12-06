import 'package:flutter/material.dart';
import '../data/local/database_service.dart';

/// Provider para acceder al servicio de base de datos local en toda la aplicación
class DatabaseProvider extends InheritedWidget {
  final DatabaseService databaseService;

  const DatabaseProvider({
    super.key,
    required this.databaseService,
    required super.child,
  });

  static DatabaseService of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<DatabaseProvider>();
    if (provider == null) {
      throw Exception('DatabaseProvider no encontrado en el contexto');
    }
    return provider.databaseService;
  }

  @override
  bool updateShouldNotify(DatabaseProvider oldWidget) {
    return databaseService != oldWidget.databaseService;
  }
}

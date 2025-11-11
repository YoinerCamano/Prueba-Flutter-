import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/connection/connection_bloc.dart' as conn;

/// ⚙️ Página de configuración del dispositivo
/// El polling de peso se detiene automáticamente al entrar aquí
class ConfigurationPage extends StatefulWidget {
  const ConfigurationPage({super.key});

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  // 📊 Estado de carga
  bool _isLoading = true;
  bool _isChangingUnit = false;

  // 📋 Datos
  String? _currentUnit;

  // 🔄 Suscripción al BLoC
  StreamSubscription? _blocSubscription;
  Timer? _timeoutTimer;

  // 🎯 Referencia al BLoC para dispose
  late final conn.ConnectionBloc _connectionBloc;

  @override
  void initState() {
    super.initState();
    print('⚙️ ConfigurationPage - Iniciando...');

    // Guardar referencia al bloc
    _connectionBloc = context.read<conn.ConnectionBloc>();

    // 🛑 DETENER POLLING DE PESO
    print('🛑 Deteniendo polling de peso...');
    _connectionBloc.add(conn.StopPolling());

    // Iniciar carga después de un pequeño delay
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _loadCurrentUnit();
      }
    });
  }

  @override
  void dispose() {
    _blocSubscription?.cancel();
    _timeoutTimer?.cancel();
    // 🔄 Reanudar polling al salir
    print('🔄 ConfigurationPage dispose - Reanudando polling...');
    _connectionBloc.add(conn.StartPolling());
    super.dispose();
  }

  /// 🔄 Cargar unidad actual
  void _loadCurrentUnit() {
    // 📊 Verificar si ya hay datos en el estado actual
    final currentState = _connectionBloc.state;
    if (currentState is conn.Connected && currentState.weightUnit != null) {
      print('📊 Unidad actual ya disponible: ${currentState.weightUnit}');
      setState(() {
        _currentUnit = currentState.weightUnit;
        _isLoading = false;
      });
    }

    // Escuchar cambios en el estado del BLoC (SIEMPRE activo)
    _blocSubscription = _connectionBloc.stream.listen((state) {
      print('🔄 Stream event recibido: ${state.runtimeType}');
      if (state is conn.Connected && mounted && state.weightUnit != null) {
        print(
            '⚖️ Unidad recibida del stream: ${state.weightUnit} (actual en UI: $_currentUnit)');

        // Cancelar timeout si está esperando
        _timeoutTimer?.cancel();

        setState(() {
          print('⚖️ Actualizando UI de $_currentUnit a ${state.weightUnit}');
          _currentUnit = state.weightUnit;
          _isLoading = false;
          _isChangingUnit = false; // Siempre limpiar flag de cambio
        });
      }
    });

    // Si no hay datos, enviar comando para consultar unidad
    if (currentState is! conn.Connected || currentState.weightUnit == null) {
      print('📤 Enviando {MSWU} para consultar unidad...');
      _connectionBloc.add(conn.SendCommandRequested('{MSWU}'));

      // Configurar timeout (2 segundos)
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _isLoading) {
          print('⏰ TIMEOUT esperando respuesta de {MSWU}');
          setState(() {
            _isLoading = false;
            _currentUnit = 'desconocida';
          });
        }
      });
    }
  }

  /// 🔄 Cambiar unidad de peso
  void _changeUnit(String targetUnit) {
    print('📤 Iniciando cambio de unidad a $targetUnit...');

    setState(() {
      _isChangingUnit = true;
    });

    // PASO 1: Consultar unidad actual
    print('📤 Paso 1: Consultando unidad actual con {MSWU}...');
    _connectionBloc.add(conn.SendCommandRequested('{MSWU}'));

    // Esperar respuesta y luego enviar comando de cambio
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      // PASO 2: Enviar comando de cambio (NO espera respuesta)
      final changeCommand = targetUnit == 'kg' ? '{MSWU0}' : '{MSWU1}';
      print('📤 Paso 2: Enviando comando de cambio $changeCommand...');
      _connectionBloc.add(conn.SendCommandRequested(changeCommand));

      // PASO 3: Esperar y volver a consultar para confirmar
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;

        print('📤 Paso 3: Confirmando cambio con {MSWU}...');
        _connectionBloc.add(conn.SendCommandRequested('{MSWU}'));

        // Timeout para todo el proceso
        _timeoutTimer?.cancel();
        _timeoutTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && _isChangingUnit) {
            print('⏰ TIMEOUT al cambiar unidad');
            setState(() {
              _isChangingUnit = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error al cambiar unidad - timeout'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        // 🔄 Al salir de la página, reanudar polling
        if (didPop) {
          print('🔄 PopScope - Reanudando polling...');
          _connectionBloc.add(conn.StartPolling());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Configuración'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // Reanudar polling antes de salir
              print('🔄 Botón back - Reanudando polling...');
              _connectionBloc.add(conn.StartPolling());
              Navigator.of(context).pop();
            },
          ),
        ),
        body: SafeArea(
          child: BlocBuilder<conn.ConnectionBloc, conn.ConnectionState>(
            builder: (context, state) {
              if (state is! conn.Connected) {
                return const Center(
                  child: Text('No conectado'),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ⚖️ Configuración de unidad de peso
                    Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.scale,
                                    size: 24, color: Colors.blue),
                                const SizedBox(width: 8),
                                Text(
                                  'Unidad de Peso',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                if (_isLoading || _isChangingUnit) ...[
                                  const Spacer(),
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Unidad actual
                            if (_currentUnit != null) ...[
                              Center(
                                child: Column(
                                  children: [
                                    const Text(
                                      'Unidad Actual',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _currentUnit == 'kg'
                                            ? Colors.blue.shade100
                                            : _currentUnit == 'lb'
                                                ? Colors.green.shade100
                                                : Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _currentUnit == 'kg'
                                              ? Colors.blue
                                              : _currentUnit == 'lb'
                                                  ? Colors.green
                                                  : Colors.grey,
                                          width: 2,
                                        ),
                                      ),
                                      child: Text(
                                        _currentUnit == 'kg'
                                            ? 'Kilogramos (kg)'
                                            : _currentUnit == 'lb'
                                                ? 'Libras (lb)'
                                                : 'Desconocida',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: _currentUnit == 'kg'
                                              ? Colors.blue.shade900
                                              : _currentUnit == 'lb'
                                                  ? Colors.green.shade900
                                                  : Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Botones para cambiar unidad
                            if (_currentUnit != null &&
                                _currentUnit != 'desconocida') ...[
                              const Text(
                                'Cambiar a:',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _currentUnit == 'kg' ||
                                              _isChangingUnit
                                          ? null
                                          : () => _changeUnit('kg'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      icon: const Icon(Icons.straighten),
                                      label: const Text(
                                        'Kilogramos',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _currentUnit == 'lb' ||
                                              _isChangingUnit
                                          ? null
                                          : () => _changeUnit('lb'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      icon: const Icon(Icons.fitness_center),
                                      label: const Text(
                                        'Libras',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            if (_isLoading && _currentUnit == null) ...[
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Column(
                                    children: [
                                      CircularProgressIndicator(),
                                      SizedBox(height: 16),
                                      Text('Consultando unidad...'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ℹ️ Información adicional
                    Card(
                      elevation: 0,
                      color: Colors.blue.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'El cambio de unidad se aplica inmediatamente en la báscula.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

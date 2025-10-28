import 'package:flutter/material.dart';
import '../../core/bluetooth_debug.dart';

/// Widget simple para pruebas de Bluetooth
class BluetoothTestPage extends StatefulWidget {
  const BluetoothTestPage({super.key});

  @override
  State<BluetoothTestPage> createState() => _BluetoothTestPageState();
}

class _BluetoothTestPageState extends State<BluetoothTestPage> {
  bool _isRunning = false;
  final _logs = <String>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prueba Bluetooth'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: _isRunning ? null : _runDiagnostic,
                  child: Text(
                      _isRunning ? 'Ejecutando...' : 'Ejecutar Diagnóstico'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isRunning
                      ? null
                      : () => _testS3Connection('DE:FD:76:A4:D7:ED'),
                  child: const Text('Test Conexión S3'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _clearLogs,
                  child: const Text('Limpiar Logs'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  return Text(
                    _logs[index],
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runDiagnostic() async {
    setState(() {
      _isRunning = true;
      _logs.clear();
      _logs.add('🔍 Iniciando diagnóstico Bluetooth...');
    });

    try {
      await BluetoothDebug.runFullDiagnostic();
      setState(() {
        _logs.add('✅ Diagnóstico completado');
      });
    } catch (e) {
      setState(() {
        _logs.add('❌ Error: $e');
      });
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  Future<void> _testS3Connection(String mac) async {
    setState(() {
      _isRunning = true;
      _logs.add('🧪 Iniciando test de conexión S3...');
    });

    try {
      await BluetoothDebug.testS3Connection(mac);
      setState(() {
        _logs.add('✅ Test de conexión completado');
      });
    } catch (e) {
      setState(() {
        _logs.add('❌ Error en test: $e');
      });
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }
}

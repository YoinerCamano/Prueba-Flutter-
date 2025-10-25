import 'package:flutter/material.dart';
import 'package:pruebas_flutter/domain/entities/ble_device.dart';

class DeviceTile extends StatelessWidget {
  final BleDevice device;
  final bool connected;
  final bool connecting;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const DeviceTile({
    super.key,
    required this.device,
    required this.connected,
    required this.connecting,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        connected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
      ),
      title: Text(device.name),
      subtitle: Text('ID: ${device.id}\nRSSI: ${device.rssi} dBm'),
      isThreeLine: true,
      trailing: _ActionButton(
        connected: connected,
        connecting: connecting,
        onConnect: onConnect,
        onDisconnect: onDisconnect,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final bool connected;
  final bool connecting;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _ActionButton({
    required this.connected,
    required this.connecting,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    if (connecting) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return connected
        ? OutlinedButton.icon(
            onPressed: onDisconnect,
            icon: const Icon(Icons.link_off),
            label: const Text('Desconectar'),
          )
        : FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.link),
            label: const Text('Conectar'),
          );
  }
}
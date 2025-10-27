import 'package:flutter/material.dart';
import '../../domain/entities.dart';

class DeviceTile extends StatelessWidget {
  final BtDevice device;
  final VoidCallback onTap;
  const DeviceTile({super.key, required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.bluetooth),
      title: Text(device.name),
      subtitle: Text(device.id),
      trailing: FilledButton(onPressed: onTap, child: const Text('Conectar')),
    );
  }
}

# Bluetooth

## Modos
- SPP: clásico, direcciones MAC con `:`
- BLE: bajo consumo, IDs variados; Tru-Test S3 usa BLE

## Repositorios
- `data/bluetooth_repository_spp*.dart`
- `data/ble/bluetooth_repository_ble.dart`
- Puente `_BridgeRepository` en `main.dart`

## Comandos
- `{RW}`: solicitar peso
- `{BV}`: solicitar voltaje
- `{BC}`: solicitar porcentaje batería
- `{MSWU}`: consultar unidad (0=kg, 1=lb)
- `{MSWU0}`/`{MSWU1}`: cambiar unidad
- `{SCZERO}`: poner en cero

## Troubleshooting
- Revisar permisos y estado de Bluetooth
- Logs en `ConnectionBloc` para parsing y secuencias
- Conexión automática: `CheckAutoConnectionRequested`

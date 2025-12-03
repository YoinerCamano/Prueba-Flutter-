# Arquitectura

## Visión general
- Flutter + BLoC para gestión de estado
- Bluetooth SPP/BLE mediante repositorios en `lib/data/`
- Persistencia en Firebase Firestore via `FirebaseService`
- UI en `presentation/pages` y `presentation/widgets`

## Flujo de datos
1. Páginas disparan eventos a BLoCs (`ConnectionBloc`, `ScanCubit`)
2. Repositorios Bluetooth envían/reciben líneas crudas
3. `ConnectionBloc` parsea datos a `WeightReading` y estados enriquecidos (`Connected`)
4. `FirebaseService` guarda mediciones y sesiones
5. `MeasurementHistoryWidget` muestra registros vía streams

## Bluetooth
- SPP (`bluetooth_repository_spp.dart`) para dispositivos clásicos
- BLE (`bluetooth_repository_ble.dart`) con `BleAdapter`
- Puente `_BridgeRepository` decide backend según ID (S3 usa BLE)

## Firebase
- Colecciones: `devices`, `measurements`, `sessions`
- Campos de mediciones: `deviceId`, `weight`, `unit`, `timestamp`, `createdAt`, `metadata`
- Orden recomendado: `orderBy('createdAt', descending: true)`

## Navegación
- `HomePage`: conexión, lectura y acciones
- `WeighingHistoryPage`: filtros, selección múltiple y borrado
- `BlePage`: escaneo BLE

## Estados clave
- `ConnectionState`: `Disconnected`, `Connecting`, `Connected`, `ConnectionError`
- `Connected` incluye `weight`, batería y `weightUnit`

# Arquitectura

## Visión general
- Flutter + BLoC para gestión de estado
- Bluetooth SPP/BLE mediante repositorios en `lib/data/`
- Persistencia en Firebase Firestore via `FirebaseService`
- UI en `presentation/pages` y `presentation/widgets`

## Flujo de datos
1. Páginas disparan eventos a BLoCs (`ConnectionBloc`, `DeviceInfoBloc`, `ScanCubit`)
2. Repositorios Bluetooth envían/reciben líneas crudas
3. `ConnectionBloc` parsea datos a `WeightReading` y estados enriquecidos (`Connected`)
4. `DeviceInfoBloc` maneja comandos técnicos independientes (`{BV}`, `{BC}`, `{ZC}`, etc.)
5. `FirebaseService` guarda mediciones y sesiones
6. `MeasurementHistoryWidget` muestra registros vía streams

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

## BLoCs

### ConnectionBloc
Maneja la conexión Bluetooth, inicialización y polling de peso:

- **Inicialización de 6 pasos** (0-3):
  - Paso 0: Modo normal (polling de peso)
  - Paso 1: Envía `{ZA1}`, espera ACK para habilitar confirmaciones
  - Paso 2: Envía `{MSWU}`, espera "kg" o "lb" para conocer unidad actual
  - Paso 3: Envía `{MSWU0}`/`{MSWU1}`, espera ACK para confirmar cambio de unidad

- **Timeouts**:
  - Inicialización (pasos 1-2): 2000ms
  - Polling de peso (`{RW}`): 120ms  
  - Cambio de unidad (paso 3): sin timeout (espera ACK indefinidamente)

- **Polling**: Ciclo continuo de `{RW}` con gap de 0ms entre comandos

### DeviceInfoBloc
Maneja comandos técnicos de información del dispositivo:

- `{BV}`: voltaje de batería
- `{BC}`: porcentaje de batería
- `{ZC}`: características del dispositivo
- Otros comandos de diagnóstico

**Separación de responsabilidades**: `ConnectionBloc` se enfoca en peso y unidades, mientras `DeviceInfoBloc` maneja datos técnicos.

### ScanCubit
Maneja el escaneo y listado de dispositivos BLE/SPP disponibles.

## Estados clave
- `ConnectionState`: `Disconnected`, `Connecting`, `Connected`, `ConnectionError`
- `Connected` incluye `weight`, batería y `weightUnit`

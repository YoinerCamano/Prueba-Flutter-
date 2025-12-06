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
- `{MSWU}`: consultar unidad (responde "kg" o "lb")
- `{MSWU0}`/`{MSWU1}`: cambiar unidad a kg/lb (responde `^` como ACK)
- `{ZA1}`: habilitar confirmación de comandos (responde `^` como ACK)
- `{SCZERO}`: poner en cero
- `{ZC}`: consultar características
- Otros comandos técnicos manejados por `DeviceInfoBloc`

## Inicialización y Cambio de Unidad

### Secuencia de Inicialización (6 pasos)
Al iniciar el polling de peso, `ConnectionBloc` ejecuta una secuencia de inicialización:

- **Paso 0**: Modo normal (no inicializando)
- **Paso 1**: `{ZA1}` enviado, esperando `^` (ACK)
- **Paso 2**: `{MSWU}` enviado, esperando respuesta "kg" o "lb"
- **Paso 3**: `{MSWU0}` o `{MSWU1}` enviado (cambio de unidad), esperando `^` (sin timeout)

Una vez completados los pasos 1-2, el sistema entra en modo de polling normal (paso 0).

### Cambio de Unidad
Cuando el usuario cambia la unidad desde `ConfigurationPage`:

1. Se envía comando directo `{MSWU0}` (kg) o `{MSWU1}` (lb)
2. `ConnectionBloc` establece `_initializationStep = 3`
3. Espera respuesta `^` (ACK) de la báscula **sin timeout**
4. Al recibir ACK, actualiza `weightUnit` en el estado
5. Retorna al polling normal (paso 0)

**Nota importante**: El paso 3 no usa timeout para evitar falsos errores. La báscula siempre responde con `^` al cambiar unidad exitosamente.

### Timeouts
- **Inicialización** (pasos 1-2): 2000ms
- **Polling de peso** (`{RW}`): 120ms
- **Cambio de unidad** (paso 3): sin timeout (espera indefinida por ACK)

## Troubleshooting
- Revisar permisos y estado de Bluetooth
- Logs en `ConnectionBloc` para parsing y secuencias
- Conexión automática: `CheckAutoConnectionRequested`

# 📊 Diagrama de Flujo: Inicialización de Unidades de Peso

## Secuencia Temporal de Eventos

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    USUARIO: Conecta a Dispositivo                       │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  BluetoothService._connect() → ConnectionBloc._onConnect()             │
│  ✓ Conexión BLE establecida                                            │
│  ✓ State: disconnected → connecting → connected                        │
│  ⚠️ Polling NO iniciado automáticamente                                │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼ (Usuario toca "Iniciar Peso")
┌─────────────────────────────────────────────────────────────────────────┐
│  UI → ConnectionBloc.add(StartPolling())                               │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ConnectionBloc._onStartPolling()                                      │
│  • _initializationStep = 0                                              │
│  • _initializationInProgress = true                                     │
│  • Envia: SendCommandRequested('{ZA1}')                                 │
│  🎯 Estado: Iniciando secuencia de comandos                             │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ConnectionBloc._onSendCommand(SendCommandRequested('{ZA1}'))          │
│  • _initializationStep = 1 (esperando respuesta)                       │
│  • CommandRegistry: registra comando saliente                           │
│  • BluetoothAdapter: envía {ZA1} al puerto serie                       │
│  📤 Estado: {ZA1} enviado a dispositivo                                │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
            ┌──────────────────┴──────────────────┐
            │                                     │
            ▼ (Esperar respuesta ~50ms)          ▼ (Timeout ~500ms)
    ┌──────────────────┐            ┌───────────────────────────┐
    │ BLE recibe:      │            │ Timer: Sin respuesta      │
    │   "^" (ACK)      │            │ Reintentar o timeout      │
    └────────┬─────────┘            └───────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ConnectionBloc._onRawLine(RawLineArrived("^"))                        │
│  • Detecta: _initializationStep == 1                                    │
│  • Valida: line == '^' (ACK)                                            │
│  • Acción: _initializationStep = 2                                      │
│  • Envía: SendCommandRequested('{MSWU}')                                │
│  ✅ Estado: {ZA1} confirmado, avanzando a paso 2                        │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ConnectionBloc._onSendCommand(SendCommandRequested('{MSWU}'))         │
│  • _initializationStep = 2 (esperando respuesta)                       │
│  • CommandRegistry: registra comando saliente                           │
│  • BluetoothAdapter: envía {MSWU} al puerto serie                      │
│  📤 Estado: {MSWU} enviado a dispositivo                               │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
            ┌──────────────────┴──────────────────┐
            │                                     │
            ▼ (Esperar respuesta ~50ms)          ▼ (Timeout ~500ms)
    ┌──────────────────┐            ┌───────────────────────────┐
    │ BLE recibe:      │            │ Timer: Sin respuesta      │
    │   "kg" o "lb"    │            │ Usar unidad por defecto   │
    └────────┬─────────┘            └───────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ConnectionBloc._onRawLine(RawLineArrived("kg"))                       │
│  • Detecta: _initializationStep == 2                                    │
│  • Valida: line contiene 'kg' o 'lb'                                    │
│  • Parse: unit = 'kg'                                                   │
│  • Acción: emit(state.copyWith(weightUnit: 'kg'))                       │
│  • Acción: _initializationStep = 0 (COMPLETADO)                         │
│  • Acción: _sendNextWeightCommand() → {RW}                              │
│  ✅ Estado: Inicialización completada, iniciando polling               │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ConnectionBloc._onSendCommand(SendCommandRequested('{RW}'))           │
│  • _weightCommandInFlight = true                                        │
│  • _startWeightTimeoutWatchdog() (120ms)                                │
│  • BluetoothAdapter: envía {RW} al puerto serie                        │
│  🎯 Estado: Entrando en polling normal de peso                          │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
            ┌──────────────────┴──────────────────┐
            │                                     │
            ▼ (Recibe peso <120ms)               ▼ (Timeout 120ms)
    ┌──────────────────────────┐     ┌──────────────────────────┐
    │ BLE recibe:              │     │ Timeout → Reintentar    │
    │   "[12.34]"              │     │ _sendNextWeightCommand() │
    │   "[U12.34]" (inestable) │     └──────────────────────────┘
    │   "[-0.5]" (negativo)    │
    │   "[---]" (sobrecarga)   │
    └────────┬─────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ConnectionBloc._onRawLine(RawLineArrived("[12.34]"))                 │
│  • Detecta: _initializationStep == 0 (modo normal)                     │
│  • Valida: RegExp encontró [valor]                                      │
│  • Parse: value = 12.34, status = stable                                │
│  • Acción: emit(state.copyWith(weight: WeightReading(...)))             │
│  • Acción: _completeWeightCommandCycle() → delay 0ms → {RW}             │
│  📊 Estado: Peso recibido y procesado                                   │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
                          (Bucle continuo de polling)
                               │
          ┌────────────────────┴────────────────────┐
          │                                         │
          ▼                                         ▼
    [Recibe peso]                          [Timeout/error]
          │                                         │
          └────────────────────┬────────────────────┘
                               │
                               ▼ (Bucle cada 120ms + 0ms)
                      ... Polling continuo ...
```

## Estados del ConnectionBloc

```
┌─────────────┐
│ disconnected│ (inicial)
└──────┬──────┘
       │ user: ConnectRequested
       ▼
┌─────────────┐
│ connecting  │ (durante conexión BLE)
└──────┬──────┘
       │ [BLE conectado exitosamente]
       ▼
┌─────────────┐
│  connected  │ (pero polling suspendido)
└──────┬──────┘
       │ user: StartPolling
       ▼
┌─────────────────────────┐
│  connected              │
│  _initializationStep:1  │ (esperando {ZA1})
└──────┬──────────────────┘
       │ [recibe: ^]
       ▼
┌─────────────────────────┐
│  connected              │
│  _initializationStep:2  │ (esperando {MSWU})
└──────┬──────────────────┘
       │ [recibe: kg/lb]
       ▼
┌─────────────────────────┐
│  connected              │
│  _initializationStep:0  │ (polling normal)
│  weightUnit: "kg"       │
│  weight: [valores]      │
└─────────────────────────┘
       │ user: StopPolling
       ▼
┌─────────────┐
│  connected  │ (_pollingSuspended = true)
└──────┬──────┘
       │ user: DisconnectRequested
       ▼
┌─────────────┐
│ disconnected│
└─────────────┘
```

## Manejo de Errores

### Escenario: {ZA1} sin respuesta (timeout)

```
Paso 1: {ZA1} enviado
    ▼ (120ms timeout en _weightTimeoutTimer)
Sin respuesta
    ▼
_weightCommandInFlight = false
_sendNextWeightCommand()
    ▼
Reintentar {ZA1} o pasar a {MSWU}
```

### Escenario: Desconexión durante inicialización

```
_initializationStep == 1 o 2
    ▼ [BLE recibe: __DISCONNECTED__]
_onRawLine() detecta línea especial
    ▼
_weightTimeoutTimer?.cancel()
emit(const ConnectionState.disconnected())
    ▼
Limpieza completa
```

### Escenario: Respuesta no esperada

```
_initializationStep == 1 (esperando ZA1)
    ▼ [BLE recibe: "algo_aleatorio"]
No coincide: line != '^' && !isEmpty && !contains('ACK')
    ▼
_onRawLine() retorna sin hacer nada
    ▼
Espera siguiente línea o timeout
```

## Variables Críticas

```
_initializationStep:
  0 = No inicializando (modo normal)
  1 = Esperando respuesta {ZA1}
  2 = Esperando respuesta {MSWU}

_initializationInProgress:
  true = En proceso de inicialización
  false = Completado o no iniciado

_weightCommandInFlight:
  true = {RW} enviado, esperando respuesta
  false = Listo para enviar siguiente {RW}

_pollingSuspended:
  true = DeviceInfoPage en pantalla (no procesar peso)
  false = Polling normal activo

_weightTimeout:
  120ms = máximo tiempo esperar respuesta de {RW}

_trackingGap:
  0ms = enviar siguiente {RW} inmediatamente tras recibir respuesta
```

## UI: Display de Unit

```
Card: Información Técnica
├─ Número de Serie: TTCSER
├─ Firmware: VA
├─ Código de Celda: SACC
├─ Celda de Carga: SCLS
├─ Microvoltios/División: SCMV
├─ Ruido CAD: SCAV
└─ Unidad de Peso: connState.weightUnit (kg/lb)
     ↑
     └─ Se actualiza cuando _onRawLine procesa {MSWU}
```

## Logs de Debugging

```
Paso 0: Inicial
🎯 === INICIANDO POLLING CON INICIALIZACIÓN ===
📤 Paso 1: Enviando {ZA1} (confirmación de comandos)

Paso 1: Enviando {ZA1}
📤 INIT: Enviando {ZA1}
✅ PESO: Comando {ZA1} enviado

Paso 1: Respuesta recibida
📥 Línea recibida: "^" | InitStep: 1
✅ INIT Paso 1: {ZA1} confirmado (ACK: ^)
➡️ INIT Paso 2: Enviando {MSWU}...

Paso 2: Enviando {MSWU}
📤 INIT: Enviando {MSWU}
✅ PESO: Comando {MSWU} enviado

Paso 2: Respuesta recibida
📥 Línea recibida: "kg" | InitStep: 2
✅ INIT Paso 2: {MSWU} recibido: kg
🎉 INIT: Secuencia completada. Iniciando polling de peso...

Modo normal: Polling
📤 PESO: Enviando {RW}
📥 PESO: "[12.34]"
📊 PESO ESTABLE: 12.34 kg
```

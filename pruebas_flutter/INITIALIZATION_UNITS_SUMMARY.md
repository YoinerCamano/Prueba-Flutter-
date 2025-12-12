# Resumen: Reimplementación de Unidades de Peso con Secuencia de Inicialización {ZA1} → {MSWU}

## 📋 Objetivo
Reimplementar el sistema de unidades de peso con una secuencia de inicialización que:
1. Envía `{ZA1}` para habilitar la confirmación de comandos
2. Envía `{MSWU}` para consultar la unidad de peso actual
3. Inicia el polling de peso solo después de completar ambos pasos

## 🔄 Flujo de Inicialización

```
ConnectionBloc._onStartPolling()
    ↓
    Establece: _initializationInProgress = true, _initializationStep = 0
    Envía: {ZA1}
    ↓
_onSendCommand recibe SendCommandRequested('{ZA1}')
    Establece: _initializationStep = 1 (esperando ACK)
    Envía: {ZA1} al dispositivo
    ↓
_onRawLine recibe respuesta ('^' o ACK)
    Detecta: _initializationStep == 1 → respuesta de {ZA1}
    Establece: _initializationStep = 2
    Envía: {MSWU}
    ↓
_onSendCommand recibe SendCommandRequested('{MSWU}')
    Establece: _initializationStep = 2 (esperando unidad)
    Envía: {MSWU} al dispositivo
    ↓
_onRawLine recibe respuesta ('kg' o 'lb')
    Detecta: _initializationStep == 2 → respuesta de {MSWU}
    Parsea unidad: 'kg' o 'lb'
    Emite: state.copyWith(weightUnit: unit)
    Establece: _initializationStep = 0 (COMPLETADO)
    Reanuda: _sendNextWeightCommand() para iniciar polling
```

## 📝 Cambios Realizados

### 1. **connection_bloc.dart** - Añadidas banderas de inicialización
```dart
// Línea ~25-30: Declaración de variables
bool _initializationInProgress = false;
int _initializationStep = 0; // 0=no inicializando, 1=esperando ZA1, 2=esperando MSWU
```

### 2. **connection_bloc.dart** - Modificado `_onStartPolling`
**Antes:**
```dart
// Enviaba {RW} directamente
_sendNextWeightCommand();
```

**Después:**
```dart
_pollingSuspended = false;
_weightCommandInFlight = false;
_initializationInProgress = true;
_initializationStep = 0;

print('🎯 === INICIANDO POLLING CON INICIALIZACIÓN ===');
print('📤 Paso 1: Enviando {ZA1} (confirmación de comandos)');
add(SendCommandRequested('{ZA1}'));
```

### 3. **connection_bloc.dart** - Extendido `_onSendCommand`
**Antes:**
```dart
// Solo chequeaba isWeightCommand para {RW}
```

**Después:**
```dart
final isInitializationCommand = e.command == '{ZA1}' || e.command == '{MSWU}';
final isWeightCommand = e.command == ScaleCommand.readWeight.code; // '{RW}'

if (isInitializationCommand) {
  print('📤 INIT: Enviando ${e.command}');
  if (e.command == '{ZA1}') {
    _initializationStep = 1; // Esperando respuesta ZA1
  } else if (e.command == '{MSWU}') {
    _initializationStep = 2; // Esperando respuesta MSWU
  }
} else if (isWeightCommand) {
  print('📤 PESO: Enviando ${e.command}');
  _weightCommandInFlight = true;
  _startWeightTimeoutWatchdog();
} else {
  print('📤 COMANDO: Enviando ${e.command}');
}
```

### 4. **connection_bloc.dart** - Reescrito `_onRawLine`
**Antes:**
```dart
// Procesaba directamente líneas de peso sin considerar inicialización
```

**Después:**
```dart
// Sección MANEJO DE INICIALIZACIÓN {ZA1} → {MSWU}
if (_initializationStep == 1) {
  // Esperando respuesta de {ZA1}
  if (line == '^' || line.isEmpty || line.contains('ACK')) {
    print('✅ INIT Paso 1: {ZA1} confirmado (ACK: $line)');
    _initializationStep = 2;
    print('➡️ INIT Paso 2: Enviando {MSWU}...');
    add(SendCommandRequested('{MSWU}'));
    return;
  }
} else if (_initializationStep == 2) {
  // Esperando respuesta de {MSWU}
  if (line.toLowerCase().contains('kg') ||
      line.toLowerCase().contains('lb') ||
      line.isNotEmpty) {
    print('✅ INIT Paso 2: {MSWU} recibido: $line');
    String unit = 'kg';
    if (line.toLowerCase().contains('lb')) {
      unit = 'lb';
    }
    emit(s.copyWith(weightUnit: unit));
    _initializationStep = 0; // INICIALIZACIÓN COMPLETADA
    _initializationInProgress = false;
    print('🎉 INIT: Secuencia completada. Iniciando polling de peso...');
    _sendNextWeightCommand();
    return;
  }
}

// Sección MODO NORMAL: PROCESAR PESO (solo si NO está en inicialización)
if (_initializationStep != 0) {
  // Aún en inicialización, ignorar línea
  return;
}
// ... resto del código de peso ...
```

### 5. **device_info_page.dart** - Añadida visualización de unidad
```dart
// En _buildTechnicalInfoCard(), después de "Ruido CAD":
_buildTechInfoRow(
  icon: Icons.scale,
  label: 'Unidad de Peso',
  value: connState.weightUnit ??
      (_isLoading ? 'Cargando...' : 'No disponible'),
),
```

### 6. **connection_state.dart** - Ya existente
```dart
// La propiedad weightUnit ya estaba declarada:
final String? weightUnit; // {MSWU} - Unidad de peso configurada (kg/lb)
```

## 🎯 Comportamiento Esperado

1. **Al conectarse:**
   - Se ejecuta `_onStartPolling()`
   - Se establece `_initializationStep = 0`
   - Se envía comando `{ZA1}`

2. **Respuesta a {ZA1}:**
   - Escala responde con `^` (ACK)
   - `_onRawLine` detecta `_initializationStep == 1`
   - Avanza a `_initializationStep = 2`
   - Envía comando `{MSWU}`

3. **Respuesta a {MSWU}:**
   - Escala responde con unidad: `kg` o `lb`
   - `_onRawLine` detecta `_initializationStep == 2`
   - Extrae y asigna `weightUnit`
   - Establece `_initializationStep = 0` (completado)
   - Inicia polling de peso con `_sendNextWeightCommand()`

4. **Polling de peso:**
   - Ahora `_initializationStep == 0`, se procesa peso normalmente
   - Timeout de 120ms y gap de 0ms se mantienen
   - Se reciben y procesan valores de peso `[valor]`, `[Uvalor]`, `[-valor]`, `[---]`

## 📊 Logs Esperados

```
🎯 === INICIANDO POLLING CON INICIALIZACIÓN ===
📤 Paso 1: Enviando {ZA1} (confirmación de comandos)
📥 Línea recibida: "^" | InitStep: 1
✅ INIT Paso 1: {ZA1} confirmado (ACK: ^)
➡️ INIT Paso 2: Enviando {MSWU}...
📤 INIT: Enviando {MSWU}
📥 Línea recibida: "kg" | InitStep: 2
✅ INIT Paso 2: {MSWU} recibido: kg
🎉 INIT: Secuencia completada. Iniciando polling de peso...
📤 PESO: Enviando {RW}
📥 PESO: "[12.34]"
📊 PESO ESTABLE: 12.34 kg
```

## ✅ Validación

- [x] Compilación sin errores críticos (`flutter analyze`)
- [x] Dependencias descargadas (`flutter pub get`)
- [x] Flujo de inicialización implementado
- [x] Manejo de respuestas {ZA1} y {MSWU}
- [x] UI actualizada con campo de unidad de peso
- [x] Polling de peso reanudado después de inicialización

## 🔍 Notas Técnicas

1. **Pasos de inicialización:**
   - `_initializationStep = 0`: No inicializando (estado normal)
   - `_initializationStep = 1`: Esperando respuesta de {ZA1}
   - `_initializationStep = 2`: Esperando respuesta de {MSWU}

2. **Detección de respuesta {ZA1}:**
   - Se acepta: `^`, línea vacía, o que contenga `ACK`
   - Respuesta típica de escala: `^` (carácter de control)

3. **Detección de respuesta {MSWU}:**
   - Se busca: `kg` o `lb` (case-insensitive)
   - Se guarda la unidad en `state.weightUnit`

4. **Cancelación de inicialización:**
   - Si polling se detiene (`_onStopPolling`), se cancela la inicialización
   - Si desconexión se detecta (`__DISCONNECTED__`), se limpia estado

## 🚀 Próximos Pasos Opcionales

1. Agregar timeout para la secuencia de inicialización (si no hay respuesta en N segundos)
2. Agregar reintentos automáticos si la inicialización falla
3. Mostrar indicador visual en la UI durante la inicialización
4. Guardar/cachear la unidad de peso entre conexiones

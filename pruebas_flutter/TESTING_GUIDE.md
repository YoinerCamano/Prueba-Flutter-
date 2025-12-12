# 🧪 Guía de Testing: Inicialización de Unidades de Peso

## Checklist de Validación

### Pre-conexión
- [ ] Asegurar que el dispositivo de escala está encendido
- [ ] Verificar que el cable serie está conectado (o emulador configurado)
- [ ] Abrir la app Flutter
- [ ] Ver que estado inicial es "disconnected"

### Conexión BLE
- [ ] Tap en "Conectar dispositivo"
- [ ] Ver que estado cambia a "connecting..."
- [ ] Seleccionar dispositivo de escala
- [ ] Ver que conexión se establece exitosamente
- [ ] State: "connected" pero polling aún no iniciado

### Iniciar Polling (Paso de Inicialización)
- [ ] Tap en "Iniciar Peso" o similar
- [ ] Observar logs:
  ```
  🎯 === INICIANDO POLLING CON INICIALIZACIÓN ===
  📤 Paso 1: Enviando {ZA1} (confirmación de comandos)
  ```
- [ ] Verificar en puerto serie (si hay monitor): `{ZA1}` fue enviado

### Fase 1: {ZA1} → ACK
- [ ] Esperar ~50-100ms
- [ ] Observar logs:
  ```
  📤 INIT: Enviando {ZA1}
  ✅ PESO: Comando {ZA1} enviado
  📥 Línea recibida: "^" | InitStep: 1
  ✅ INIT Paso 1: {ZA1} confirmado (ACK: ^)
  ➡️ INIT Paso 2: Enviando {MSWU}...
  ```
- [ ] **Crítico:** Debe avanzar automáticamente a Paso 2

### Fase 2: {MSWU} → Unidad
- [ ] Esperar ~50-100ms
- [ ] Observar logs:
  ```
  📤 INIT: Enviando {MSWU}
  ✅ PESO: Comando {MSWU} enviado
  📥 Línea recibida: "kg" | InitStep: 2
  ✅ INIT Paso 2: {MSWU} recibido: kg
  🎉 INIT: Secuencia completada. Iniciando polling de peso...
  ```
- [ ] **Crítico:** Debe completar inicialización

### Fase 3: Polling de Peso
- [ ] Observar logs comenzando con polling:
  ```
  📤 PESO: Enviando {RW}
  📥 PESO: "[12.34]"
  📊 PESO ESTABLE: 12.34 kg
  ```
- [ ] Colocar peso en escala
- [ ] Ver valores actualizados en UI
- [ ] Ver que cada lectura lleva ~120ms (timeout watchdog)
- [ ] Gap de 0ms = envío inmediato de siguiente {RW}

### Validación en UI
- [ ] Ir a "Info del Dispositivo"
- [ ] Ver campo "Unidad de Peso: kg" (o "lb")
- [ ] Ver que otros datos técnicos se actualizan normalmente
- [ ] Volver a pantalla de peso
- [ ] Polling debe reanudar después de salir de Info

## Escenarios de Error

### Error: {ZA1} sin respuesta

**Síntoma:**
```
📤 INIT: Enviando {ZA1}
... espera >120ms ...
(nada más)
```

**Causa posible:**
- Escala no conectada correctamente
- Cable serie defectuoso
- Puerto COM erróneo

**Solución:**
1. Verificar conexión física
2. Comprobar puerto serie en dispositivo
3. Reintentar conexión completa

### Error: {ZA1} OK pero {MSWU} sin respuesta

**Síntoma:**
```
✅ INIT Paso 1: {ZA1} confirmado (ACK: ^)
➡️ INIT Paso 2: Enviando {MSWU}...
📤 INIT: Enviando {MSWU}
... espera >120ms ...
(nada más)
```

**Causa posible:**
- Escala no soporta {MSWU}
- Respuesta inesperada

**Solución:**
1. Verificar documentación de escala para comando {MSWU}
2. Verificar respuesta en monitor serie
3. Ajustar lógica de detección si formato es diferente

### Error: Unidad no aparece en UI

**Síntoma:**
```
Unidad de Peso: No disponible
```

**Causa posible:**
- Inicialización no completada (_initializationStep ≠ 0)
- Response no fue parseada correctamente

**Solución:**
1. Ver logs de inicialización
2. Verificar que _initializationStep llegó a 0
3. Verificar que state.copyWith(weightUnit:) fue emitido

## Logs de Debugging Esperados (Secuencia Completa)

```
=== INICIO DE CONEXIÓN ===
🎯 Iniciando conexión a: <device_id>
✅ Conexión establecida → Listo para polling de peso

=== INICIO DE POLLING ===
🎯 === INICIANDO POLLING CON INICIALIZACIÓN ===
📤 Paso 1: Enviando {ZA1} (confirmación de comandos)
📤 INIT: Enviando {ZA1}
✅ PESO: Comando {ZA1} enviado

=== RESPUESTA ZA1 ===
📥 Línea recibida: "^" | InitStep: 1
✅ INIT Paso 1: {ZA1} confirmado (ACK: ^)
➡️ INIT Paso 2: Enviando {MSWU}...
📤 INIT: Enviando {MSWU}
✅ PESO: Comando {MSWU} enviado

=== RESPUESTA MSWU ===
📥 Línea recibida: "kg" | InitStep: 2
✅ INIT Paso 2: {MSWU} recibido: kg
🎉 INIT: Secuencia completada. Iniciando polling de peso...

=== POLLING NORMAL ===
📤 PESO: Enviando {RW}
📥 PESO: "[12.34]"
📊 PESO ESTABLE: 12.34 kg
📤 PESO: Enviando {RW}
📥 PESO: "[U12.34]"
📊 PESO INESTABLE: 12.34 kg
📤 PESO: Enviando {RW}
📥 PESO: "[---]"
⚠️ SOBRECARGA DETECTADA: [---]

=== PANTALLA DE INFO DE DISPOSITIVO ===
🛑 Deteniendo polling de peso...
(... comandos técnicos ejecutándose ...)
Unidad de Peso: kg
🔄 Reanudando polling...
```

## Pruebas Específicas

### Test 1: Conmutación de Pantallas
1. Iniciar polling
2. Verificar peso en tiempo real
3. Ir a "Info de Dispositivo"
4. Polling debe detenerse
5. Ver "Unidad de Peso: kg" en info
6. Volver a pantalla anterior
7. Polling debe reanudar

**Resultado esperado:** ✓ Transición suave sin perdida de datos

### Test 2: Reinicio de Conexión
1. Iniciar polling (ve {ZA1} → {MSWU})
2. Desconectar dispositivo
3. Reconectar
4. Volver a iniciar polling
5. Secuencia {ZA1} → {MSWU} debe repetirse

**Resultado esperado:** ✓ Inicialización se repite correctamente

### Test 3: Cambio de Unidad
1. Escala con kg
2. Iniciar polling → "Unidad: kg"
3. Cambiar escala a lb manualmente
4. Desconectar/reconectar
5. Iniciar polling nuevamente
6. Debe mostrar "Unidad: lb"

**Resultado esperado:** ✓ Nueva unidad se detecta correctamente

### Test 4: Manejo de Errores
1. Desconectar BLE durante inicialización (paso 1 o 2)
2. Observe estado final: "disconnected"
3. Reconectar y reintentar

**Resultado esperado:** ✓ Sin crashes, estado consistente

## Performance Metrics

```
Métrica                     Valor Esperado      Valor Aceptable
─────────────────────────────────────────────────────────────
Tiempo {ZA1} → ACK         ~50-100ms           <200ms
Tiempo {MSWU} → Unidad     ~50-100ms           <200ms
Tiempo total inicialización ~100-200ms         <400ms
Timeout de peso ({RW})     120ms               ±10ms
Gap entre {RW}             0ms                 0ms
Lecturas/segundo           ~8-10               >5
CPU durante polling        <10%                <20%
```

## Comandos Serial Útiles (Para Monitor)

Si tienes un monitor serial (ej: PuTTY, Arduino IDE):

```
# Esperar a ver:
{ZA1}           ← Enviado por app

^               ← Respuesta escala (típicamente)
kg              ← Respuesta escala para MSWU

# Luego:
{RW}            ← Enviado por app
[12.34]         ← Respuesta escala
{RW}            ← Enviado por app
[U12.34]        ← Respuesta escala (inestable)
```

## Notas Importantes

1. **Timeout de 120ms:** Si no hay respuesta en 120ms, se considera timeout y se reintenta
2. **Gap de 0ms:** Significa envío inmediato, sin delay entre ciclos
3. **Inicialización = Bloqueante:** Mientras está en pasos 1-2, NO se procesan otras líneas
4. **weightUnit persiste:** Se mantiene en estado hasta desconexión
5. **Reinicia en cada conexión:** La secuencia {ZA1} → {MSWU} se ejecuta cada conexión nueva

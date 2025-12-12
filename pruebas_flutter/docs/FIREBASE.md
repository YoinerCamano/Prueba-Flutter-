# Firebase

## Colecciones
- `devices`: registro y última conexión
- `measurements`: mediciones de peso
- `sessions`: sesiones de pesaje

## Mediciones
Campos:
- `deviceId: string`
- `weight: number`
- `unit: 'kg'|'lb'`
- `timestamp: serverTimestamp`
- `createdAt: DateTime(UTC)`
- `metadata: object`

## Consultas
- Orden recomendado: `orderBy('createdAt', descending: true)`
- Filtros por rango: `where('createdAt', >= startDate)`, `<= endDate`
- Evitar múltiples `orderBy` sin índice compuesto

## Reglas (ejemplo básico)
```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /measurements/{id} {
      allow read, write: if true; // ajustar según necesidades
    }
  }
}
```

## Índices
Si necesitas `orderBy` + múltiples `where`, crea índices desde la consola de Firestore.

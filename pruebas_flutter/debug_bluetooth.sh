#!/bin/bash

echo "🔧 ================================"
echo "🔧 === HERRAMIENTAS DE DEBUG ==="
echo "🔧 ================================"
echo ""

echo "1. Limpiando caché de Flutter..."
flutter clean

echo ""
echo "2. Obteniendo dependencias..."
flutter pub get

echo ""
echo "3. Revisando problemas de código..."
flutter analyze

echo ""
echo "4. Compilando en modo debug..."
flutter build apk --debug

echo ""
echo "5. Ejecutando en dispositivo (con logs detallados)..."
echo "   NOTA: Conecta tu dispositivo Android y asegúrate de que"
echo "   - Depuración USB esté habilitada"
echo "   - El dispositivo aparezca en 'flutter devices'"
echo ""

read -p "¿Deseas ejecutar la app ahora? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "▶️ Ejecutando con logs detallados..."
    flutter run --verbose
else
    echo "ℹ️ Para ejecutar manualmente:"
    echo "   flutter run --verbose"
fi

echo ""
echo "🔧 ================================"
echo "🔧 === COMANDOS ÚTILES ==="
echo "🔧 ================================"
echo ""
echo "📱 Ver dispositivos conectados:"
echo "   flutter devices"
echo ""
echo "📱 Ver logs en tiempo real:"
echo "   flutter logs"
echo ""
echo "📱 Ejecutar con logs detallados:"
echo "   flutter run --verbose"
echo ""
echo "📱 Hot reload durante ejecución:"
echo "   Presiona 'r' en la terminal"
echo ""
echo "📱 Hot restart durante ejecución:"
echo "   Presiona 'R' en la terminal"
echo ""
echo "🔧 ================================"
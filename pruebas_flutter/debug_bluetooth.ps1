Write-Host "🔧 ================================" -ForegroundColor Cyan
Write-Host "🔧 === HERRAMIENTAS DE DEBUG ===" -ForegroundColor Cyan
Write-Host "🔧 ================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "1. Limpiando caché de Flutter..." -ForegroundColor Yellow
flutter clean

Write-Host ""
Write-Host "2. Obteniendo dependencias..." -ForegroundColor Yellow
flutter pub get

Write-Host ""
Write-Host "3. Revisando problemas de código..." -ForegroundColor Yellow
flutter analyze

Write-Host ""
Write-Host "4. Compilando en modo debug..." -ForegroundColor Yellow
flutter build apk --debug

Write-Host ""
Write-Host "5. Ejecutando en dispositivo (con logs detallados)..." -ForegroundColor Yellow
Write-Host "   NOTA: Conecta tu dispositivo Android y asegúrate de que" -ForegroundColor Gray
Write-Host "   - Depuración USB esté habilitada" -ForegroundColor Gray
Write-Host "   - El dispositivo aparezca en 'flutter devices'" -ForegroundColor Gray
Write-Host ""

$respuesta = Read-Host "¿Deseas ejecutar la app ahora? (y/n)"
if ($respuesta -eq "y" -or $respuesta -eq "Y") {
    Write-Host "▶️ Ejecutando con logs detallados..." -ForegroundColor Green
    flutter run --verbose
} else {
    Write-Host "ℹ️ Para ejecutar manualmente:" -ForegroundColor Blue
    Write-Host "   flutter run --verbose" -ForegroundColor Blue
}

Write-Host ""
Write-Host "🔧 ================================" -ForegroundColor Cyan
Write-Host "🔧 === COMANDOS ÚTILES ===" -ForegroundColor Cyan
Write-Host "🔧 ================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📱 Ver dispositivos conectados:" -ForegroundColor Green
Write-Host "   flutter devices" -ForegroundColor Gray
Write-Host ""
Write-Host "📱 Ver logs en tiempo real:" -ForegroundColor Green
Write-Host "   flutter logs" -ForegroundColor Gray
Write-Host ""
Write-Host "📱 Ejecutar con logs detallados:" -ForegroundColor Green
Write-Host "   flutter run --verbose" -ForegroundColor Gray
Write-Host ""
Write-Host "📱 Hot reload durante ejecución:" -ForegroundColor Green
Write-Host "   Presiona 'r' en la terminal" -ForegroundColor Gray
Write-Host ""
Write-Host "📱 Hot restart durante ejecución:" -ForegroundColor Green
Write-Host "   Presiona 'R' en la terminal" -ForegroundColor Gray
Write-Host ""
Write-Host "🔧 ================================" -ForegroundColor Cyan
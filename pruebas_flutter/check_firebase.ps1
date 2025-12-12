# Script de verificación de configuración de Firebase
Write-Host "🔍 Verificando configuración de Firebase..." -ForegroundColor Cyan
Write-Host ""

$allOk = $true

# 1. Verificar google-services.json
Write-Host "1. Verificando google-services.json..." -NoNewline
$googleServicesPath = "android/app/google-services.json"
if (Test-Path $googleServicesPath) {
    Write-Host " ✅" -ForegroundColor Green
    
    # Verificar contenido
    $content = Get-Content $googleServicesPath -Raw | ConvertFrom-Json
    $packageName = $content.client[0].client_info.android_client_info.package_name
    
    Write-Host "   Package name en google-services.json: $packageName" -ForegroundColor Yellow
    
    if ($packageName -eq "com.example.pruebas_flutter") {
        Write-Host "   ✅ Package name correcto" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Package name incorrecto. Debe ser: com.example.pruebas_flutter" -ForegroundColor Red
        $allOk = $false
    }
} else {
    Write-Host " ❌" -ForegroundColor Red
    Write-Host "   Descarga google-services.json de Firebase Console" -ForegroundColor Yellow
    Write-Host "   y colócalo en: android/app/google-services.json" -ForegroundColor Yellow
    $allOk = $false
}

Write-Host ""

# 2. Verificar firebase_options.dart
Write-Host "2. Verificando firebase_options.dart..." -NoNewline
$firebaseOptionsPath = "lib/firebase_options.dart"
if (Test-Path $firebaseOptionsPath) {
    $content = Get-Content $firebaseOptionsPath -Raw
    
    if ($content -match "YOUR_ANDROID_API_KEY" -or $content -match "YOUR_") {
        Write-Host " ⚠️" -ForegroundColor Yellow
        Write-Host "   Aún contiene placeholders (YOUR_...)" -ForegroundColor Yellow
        Write-Host "   Actualiza con tus credenciales de Firebase Console" -ForegroundColor Yellow
        $allOk = $false
    } else {
        Write-Host " ✅" -ForegroundColor Green
    }
} else {
    Write-Host " ❌" -ForegroundColor Red
    $allOk = $false
}

Write-Host ""

# 3. Verificar android/settings.gradle.kts
Write-Host "3. Verificando android/settings.gradle.kts..." -NoNewline
$settingsGradlePath = "android/settings.gradle.kts"
if (Test-Path $settingsGradlePath) {
    $content = Get-Content $settingsGradlePath -Raw
    
    if ($content -match "com.google.gms.google-services") {
        Write-Host " ✅" -ForegroundColor Green
    } else {
        Write-Host " ❌" -ForegroundColor Red
        Write-Host "   Falta el plugin de Google Services" -ForegroundColor Yellow
        $allOk = $false
    }
} else {
    Write-Host " ❌" -ForegroundColor Red
    $allOk = $false
}

Write-Host ""

# 4. Verificar android/app/build.gradle.kts
Write-Host "4. Verificando android/app/build.gradle.kts..." -NoNewline
$appGradlePath = "android/app/build.gradle.kts"
if (Test-Path $appGradlePath) {
    $content = Get-Content $appGradlePath -Raw
    
    if ($content -match "com.google.gms.google-services") {
        Write-Host " ✅" -ForegroundColor Green
        
        # Verificar minSdk
        if ($content -match 'minSdk\s*=\s*(\d+)') {
            $minSdk = $matches[1]
            if ([int]$minSdk -ge 21) {
                Write-Host "   ✅ minSdk = $minSdk (Firebase requiere >= 21)" -ForegroundColor Green
            } else {
                Write-Host "   ⚠️ minSdk = $minSdk (recomendado >= 21)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host " ❌" -ForegroundColor Red
        Write-Host "   Falta el plugin de Google Services" -ForegroundColor Yellow
        $allOk = $false
    }
} else {
    Write-Host " ❌" -ForegroundColor Red
    $allOk = $false
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""

if ($allOk) {
    Write-Host "🎉 ¡Todo está configurado correctamente!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Próximos pasos:" -ForegroundColor Cyan
    Write-Host "1. Ejecuta: flutter clean" -ForegroundColor White
    Write-Host "2. Ejecuta: flutter pub get" -ForegroundColor White
    Write-Host "3. Ejecuta: flutter run" -ForegroundColor White
    Write-Host ""
    Write-Host "Deberías ver: ✅ Firebase inicializado correctamente" -ForegroundColor Green
} else {
    Write-Host "⚠️ Hay algunos problemas que resolver" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Revisa los errores arriba y sigue las instrucciones en:" -ForegroundColor White
    Write-Host "SOLUCION_ERROR_FIREBASE.md" -ForegroundColor Cyan
}

Write-Host ""

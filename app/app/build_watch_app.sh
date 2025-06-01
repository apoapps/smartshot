#!/bin/bash

# Script para compilar e instalar la aplicación del Apple Watch
# Asegúrate de tener tu Apple Watch conectado y emparejado

echo "🔄 Compilando e instalando aplicación del Apple Watch..."

# Cambiar al directorio de iOS
cd ios

# Limpiar build anterior
echo "🧹 Limpiando builds anteriores..."
xcodebuild clean -scheme "watch Watch App" -configuration Debug

# Compilar la aplicación del Watch
echo "🔨 Compilando aplicación del Apple Watch..."
xcodebuild build -scheme "watch Watch App" -configuration Debug -destination generic/platform=watchOS

# Verificar si la compilación fue exitosa
if [ $? -eq 0 ]; then
    echo "✅ Compilación exitosa"
    
    # Intentar instalar en el Apple Watch (requiere que esté conectado)
    echo "📱 Instalando en Apple Watch..."
    xcodebuild install -scheme "watch Watch App" -configuration Debug -destination generic/platform=watchOS
    
    if [ $? -eq 0 ]; then
        echo "✅ Aplicación instalada exitosamente en el Apple Watch"
        echo "📱 Abre la aplicación SmartShot en tu Apple Watch para completar la configuración"
    else
        echo "⚠️ Error al instalar en el Apple Watch. Asegúrate de que:"
        echo "   - Tu Apple Watch esté conectado y emparejado"
        echo "   - Tengas permisos de desarrollador configurados"
        echo "   - El Apple Watch esté desbloqueado"
    fi
else
    echo "❌ Error en la compilación"
    exit 1
fi

echo "🎉 Proceso completado" 
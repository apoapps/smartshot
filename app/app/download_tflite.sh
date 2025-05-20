#!/bin/bash
# Script para descargar bibliotecas nativas TensorFlow Lite para Android e iOS

# Crear directorios si no existen
mkdir -p android/app/src/main/jniLibs/arm64-v8a
mkdir -p android/app/src/main/jniLibs/armeabi-v7a
mkdir -p android/app/src/main/jniLibs/x86
mkdir -p android/app/src/main/jniLibs/x86_64
mkdir -p ios/Frameworks

# URLs de descarga
ARM64_V8A="https://github.com/the-guild-of-thick-coated-drafts/tflite-dist/raw/main/android/arm64-v8a/libtensorflowlite_c.so"
ARMEABI_V7A="https://github.com/the-guild-of-thick-coated-drafts/tflite-dist/raw/main/android/armeabi-v7a/libtensorflowlite_c.so"
X86="https://github.com/the-guild-of-thick-coated-drafts/tflite-dist/raw/main/android/x86/libtensorflowlite_c.so"
X86_64="https://github.com/the-guild-of-thick-coated-drafts/tflite-dist/raw/main/android/x86_64/libtensorflowlite_c.so"
IOS="https://github.com/the-guild-of-thick-coated-drafts/tflite-dist/raw/main/ios/TensorFlowLiteC.framework.zip"

# Descargar bibliotecas Android
echo "Descargando bibliotecas para Android..."
curl -L $ARM64_V8A -o android/app/src/main/jniLibs/arm64-v8a/libtensorflowlite_c.so
curl -L $ARMEABI_V7A -o android/app/src/main/jniLibs/armeabi-v7a/libtensorflowlite_c.so
curl -L $X86 -o android/app/src/main/jniLibs/x86/libtensorflowlite_c.so
curl -L $X86_64 -o android/app/src/main/jniLibs/x86_64/libtensorflowlite_c.so

# Descargar y descomprimir biblioteca iOS
echo "Descargando biblioteca para iOS..."
curl -L $IOS -o ios/TensorFlowLiteC.framework.zip
cd ios
unzip -o TensorFlowLiteC.framework.zip
rm TensorFlowLiteC.framework.zip
cd ..

echo "Instalación completada." 
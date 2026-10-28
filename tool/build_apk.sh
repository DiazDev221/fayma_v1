#!/usr/bin/env bash
# Construit des APK release allégés : un fichier par architecture CPU.
set -euo pipefail

cd "$(dirname "$0")/.."

flutter build apk \
  --release \
  --split-per-abi \
  --obfuscate \
  --split-debug-info=build/symbols

echo
echo "APK générés :"
ls -lh build/app/outputs/flutter-apk/*.apk

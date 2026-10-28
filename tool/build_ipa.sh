#!/usr/bin/env bash
# Construit l'archive iOS et l'IPA signé (TestFlight / App Store).
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "La compilation iOS nécessite macOS et Xcode." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Xcode est introuvable. Installez Xcode depuis le Mac App Store." >&2
  exit 1
fi

flutter build ipa \
  --release \
  --obfuscate \
  --split-debug-info=build/symbols

echo
echo "IPA généré :"
ls -lh build/ios/ipa/*.ipa

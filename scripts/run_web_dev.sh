#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFINES_FILE="$ROOT_DIR/dart_defines.local.json"

if [[ ! -f "$DEFINES_FILE" ]]; then
  echo "Missing $DEFINES_FILE"
  echo "Create it from dart_defines.local.json.example and set SUPABASE_URL + SUPABASE_ANON_KEY."
  exit 1
fi

cd "$ROOT_DIR"
flutter run -d chrome --dart-define-from-file="$DEFINES_FILE"

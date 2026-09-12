#!/usr/bin/env bash
# Validate that a Unity project's C# compiles, headless, without opening the Editor.
#
# Usage: validate-compile.sh [-p PROJECT_PATH] [-u UNITY_BINARY] [-t BUILD_TARGET] [-l LOG_FILE]
# Exit:  0 = compiled clean | 1 = usage/environment error | 2 = compilation errors
set -euo pipefail

PROJECT_PATH="$PWD"
UNITY_BIN="${UNITY_PATH:-}"
BUILD_TARGET=""
LOG_FILE=""

usage() { sed -n '2,6p' "$0"; exit 1; }

while getopts ":p:u:t:l:h" opt; do
  case "$opt" in
    p) PROJECT_PATH="$OPTARG" ;;
    u) UNITY_BIN="$OPTARG" ;;
    t) BUILD_TARGET="$OPTARG" ;;
    l) LOG_FILE="$OPTARG" ;;
    *) usage ;;
  esac
done

detect_unity() {
  [ -n "$UNITY_BIN" ] && { printf '%s\n' "$UNITY_BIN"; return 0; }
  for candidate in Unity unity-editor; do
    if command -v "$candidate" >/dev/null 2>&1; then command -v "$candidate"; return 0; fi
  done
  local hub=""
  for h in "unityhub" "/Applications/Unity Hub.app/Contents/MacOS/Unity Hub"; do
    if command -v "$h" >/dev/null 2>&1 || [ -x "$h" ]; then hub="$h"; break; fi
  done
  if [ -n "$hub" ]; then
    "$hub" --headless editors --installed 2>/dev/null \
      | sed -n 's/.*installed at \(.*\)$/\1/p' | head -n 1
  fi
}

UNITY_BIN="$(detect_unity || true)"
if [ -z "$UNITY_BIN" ] || { [ ! -x "$UNITY_BIN" ] && ! command -v "$UNITY_BIN" >/dev/null 2>&1; }; then
  echo "error: Unity binary not found. Set UNITY_PATH or pass -u <path>." >&2
  exit 1
fi
if [ ! -d "$PROJECT_PATH/Assets" ]; then
  echo "error: '$PROJECT_PATH' is not a Unity project (no Assets/ directory)." >&2
  exit 1
fi

LOG_FILE="${LOG_FILE:-$(mktemp -t unity-compile.XXXXXX.log)}"
mkdir -p "$(dirname "$LOG_FILE")"

echo "==> Unity:   $UNITY_BIN"
echo "==> Project: $PROJECT_PATH"
echo "==> Log:     $LOG_FILE"

args=(-batchmode -quit -nographics -projectPath "$PROJECT_PATH" -logFile - -disable-assembly-updater)
[ -n "$BUILD_TARGET" ] && args+=(-buildTarget "$BUILD_TARGET")

set +e
"$UNITY_BIN" "${args[@]}" 2>&1 | tee "$LOG_FILE"
status=${PIPESTATUS[0]}
set -e

if grep -qE "error CS[0-9]+" "$LOG_FILE"; then
  echo "==> FAILED: C# compilation errors" >&2
  grep -E "error CS[0-9]+" "$LOG_FILE" | sort -u | head -n 40 >&2
  exit 2
fi
if [ "$status" -ne 0 ]; then
  echo "==> FAILED: Unity exited with code $status" >&2
  exit 2
fi
echo "==> OK: project compiles cleanly"

#!/usr/bin/env bash
# Run Unity Test Framework suites from the command line and export NUnit XML reports.
#
# Usage: run-tests.sh [-p PROJECT_PATH] [-u UNITY_BINARY] [-m EditMode|PlayMode|all] [-o OUT_DIR]
#                     [-f TEST_FILTER] [-c TEST_CATEGORY] [-a ASSEMBLY_NAMES]
# Exit:  0 = all passed | 1 = usage/environment error | 2 = test failures | 3 = run failure
set -euo pipefail

PROJECT_PATH="$PWD"
UNITY_BIN="${UNITY_PATH:-}"
MODE="all"
OUT_DIR="artifacts/test-results"
FILTER=""; CATEGORY=""; ASSEMBLIES=""

usage() { sed -n '2,7p' "$0"; exit 1; }

while getopts ":p:u:m:o:f:c:a:h" opt; do
  case "$opt" in
    p) PROJECT_PATH="$OPTARG" ;;
    u) UNITY_BIN="$OPTARG" ;;
    m) MODE="$OPTARG" ;;
    o) OUT_DIR="$OPTARG" ;;
    f) FILTER="$OPTARG" ;;
    c) CATEGORY="$OPTARG" ;;
    a) ASSEMBLIES="$OPTARG" ;;
    *) usage ;;
  esac
done

detect_unity() {
  [ -n "$UNITY_BIN" ] && { printf '%s\n' "$UNITY_BIN"; return 0; }
  for candidate in Unity unity-editor; do
    if command -v "$candidate" >/dev/null 2>&1; then command -v "$candidate"; return 0; fi
  done
  for h in "unityhub" "/Applications/Unity Hub.app/Contents/MacOS/Unity Hub"; do
    if command -v "$h" >/dev/null 2>&1 || [ -x "$h" ]; then
      "$h" --headless editors --installed 2>/dev/null \
        | sed -n 's/.*installed at \(.*\)$/\1/p' | head -n 1
      return 0
    fi
  done
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

case "$MODE" in
  all) PLATFORMS=(EditMode PlayMode) ;;
  EditMode|PlayMode) PLATFORMS=("$MODE") ;;
  *) echo "error: -m must be EditMode, PlayMode, or all" >&2; exit 1 ;;
esac

mkdir -p "$OUT_DIR"
overall=0

parse_report() {
  python3 - "$1" <<'PY'
import sys, xml.etree.ElementTree as ET
try:
    run = ET.parse(sys.argv[1]).getroot()
except Exception as exc:
    print(f"could not parse report: {exc}"); sys.exit(3)
print(f"result={run.get('result')} total={run.get('total')} "
      f"passed={run.get('passed')} failed={run.get('failed')} skipped={run.get('skipped')}")
sys.exit(0 if run.get("result") == "Passed" else 2)
PY
}

for platform in "${PLATFORMS[@]}"; do
  report="$(cd "$(dirname "$OUT_DIR")" && pwd)/$(basename "$OUT_DIR")/${platform,,}-results.xml"
  echo "==> Running $platform tests -> $report"
  args=(-batchmode -runTests -nographics -projectPath "$PROJECT_PATH"
        -testPlatform "$platform" -testResults "$report" -logFile -)
  [ -n "$FILTER" ]     && args+=(-testFilter "$FILTER")
  [ -n "$CATEGORY" ]   && args+=(-testCategory "$CATEGORY")
  [ -n "$ASSEMBLIES" ] && args+=(-assemblyNames "$ASSEMBLIES")

  set +e
  "$UNITY_BIN" "${args[@]}"
  status=$?
  set -e

  if [ -f "$report" ]; then
    set +e
    parse_report "$report"
    parsed=$?
    set -e
    [ "$parsed" -ne 0 ] && overall=$parsed
  else
    echo "==> $platform: no report produced (exit $status)" >&2
    overall=3
  fi
  [ "$status" -ge 3 ] && overall=3
done

if [ "$overall" -eq 0 ]; then echo "==> OK: all tests passed"; else echo "==> FAILED (code $overall)" >&2; fi
exit "$overall"

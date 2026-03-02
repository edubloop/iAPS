#!/usr/bin/env bash
# run_tir_tests.sh — Run Track 1 TIR engine tests via swift test.
#
# Usage (from repo root):
#   bash BuildTools/run_tir_tests.sh
#
# Engine source files are copied fresh from their canonical locations each run
# so tests always reflect the current engine code.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$REPO_ROOT/BuildTools/TIREngineTests"
ENGINE_SRC="$REPO_ROOT/FreeAPS/Sources/Modules/TIRAnalysis/Engine"
TESTS_SRC="$REPO_ROOT/FreeAPSTests/TIRAnalysis"
ENGINE_DST="$PKG/Sources/FreeAPS/Engine"
TESTS_DST="$PKG/Tests/FreeAPSTests"

echo "==> Syncing engine source files..."
cp -f "$ENGINE_SRC/TIRModels.swift"                  "$ENGINE_DST/"
cp -f "$ENGINE_SRC/ThresholdCrossingDetector.swift"  "$ENGINE_DST/"
cp -f "$ENGINE_SRC/EventClassifier.swift"            "$ENGINE_DST/"
cp -f "$ENGINE_SRC/TIRAnalysisEngine.swift"          "$ENGINE_DST/"
cp -f "$ENGINE_SRC/TIRSettingsAuditor.swift"         "$ENGINE_DST/"

echo "==> Syncing test files..."
cp -f "$TESTS_SRC/TIRThresholdCrossingDetectorTests.swift" "$TESTS_DST/"
cp -f "$TESTS_SRC/TIRAnalysisEngineTests.swift"            "$TESTS_DST/"
cp -f "$TESTS_SRC/TIRSettingsAuditorTests.swift"           "$TESTS_DST/"

echo "==> Running swift test..."
swift test --package-path "$PKG" "$@"

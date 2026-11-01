#!/bin/bash
# cov.sh — line coverage for this module's *_test suites.
#
# Builds ONE coverage-instrumented harness that imports every non-live
# *_test module (module main files are skipped — they're standalone
# live-integration programs), runs it under `skink -cov`, and reports
# per-file and total line coverage via skinkcov.
#
# Usage:   ./cov.sh [--lcov] — --lcov also writes coverage.info beside
#          this script (LCOV format for editor coverage gutters/CI).
#
# Requires: skink, skinkcov (build: make -C ../../tools/skinkcov).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "${SKINK:-}" ]; then
    SKINK_BIN="$SKINK"
elif command -v skink >/dev/null 2>&1; then
    SKINK_BIN="$(command -v skink)"
elif [ -x "$HOME/.local/skink/bin/skink" ]; then
    SKINK_BIN="$HOME/.local/skink/bin/skink"
else
    echo "skink binary not found (set SKINK)"; exit 1
fi
SKINK_HOME="${SKINK_HOME:-$HOME/.local/skink/std}"
export SKINK_HOME

SKINKCOV="${SKINKCOV:-$SCRIPT_DIR/../../tools/skinkcov/skinkcov}"
[ -x "$SKINKCOV" ] || { echo "skinkcov not found at $SKINKCOV (run: make -C $SCRIPT_DIR/../../tools/skinkcov)"; exit 1; }

# Generate the harness: one import per test module, one call per Test*.
MAIN="$SCRIPT_DIR/.cov_main.skink"
{
    echo 'module main'
    echo 'import "std/testing"'
    for f in "$SCRIPT_DIR"/*_test.skink; do
        mod=$(grep -m1 '^module ' "$f" | awk '{print $2}')
        [ "$mod" = "main" ] && continue
        echo "import \"$mod\""
    done
    echo 'fn main() -> int {'
    for f in "$SCRIPT_DIR"/*_test.skink; do
        mod=$(grep -m1 '^module ' "$f" | awk '{print $2}')
        [ "$mod" = "main" ] && continue
        for fn in $(grep -oE '^pub fn (Test[A-Za-z0-9_]+)' "$f" | sed 's/pub fn //'); do
            echo '    testing.Reset()'
            echo "    $mod.$fn()"
        done
    done
    echo '    return 0'
    echo '}'
} > "$MAIN"

BIN="$(mktemp -u /tmp/cov_bin.XXXXXX)"
LCOV=""
if [ "${1:-}" = "--lcov" ]; then
    LCOV="$SCRIPT_DIR/coverage.info"
fi
trap 'rm -f "$MAIN" "$BIN" "$BIN.skinkcov"' EXIT

SKINK_HOME="$SKINK_HOME" "$SKINK_BIN" -cov -o "$BIN" "$MAIN" || exit 1
SKINK_COV_OUT="$BIN.skinkcov" "$BIN" || true
"$SKINKCOV" "$BIN.skinkcov"
if [ -n "$LCOV" ]; then
    "$SKINKCOV" "$BIN.skinkcov" -lcov "$LCOV"
    echo "lcov written: $LCOV"
fi

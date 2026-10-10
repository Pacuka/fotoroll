#!/usr/bin/env bash
# Runs each integration test in the real Linux app, one at a time
# (flutter can't start the desktop app twice in a single `flutter test` run).
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
for f in integration_test/*_test.dart; do
  echo "== $f"
  if ! flutter test "$f" -d linux 2>&1 | grep -E "All tests passed|Some tests failed|Expected|Actual|reason"; then
    status=1
  fi
done
exit $status

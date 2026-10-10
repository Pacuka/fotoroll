#!/usr/bin/env bash
# Runs each integration test in the real Linux app, one at a time
# (flutter can't start the desktop app twice in a single `flutter test` run).
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
for f in integration_test/*_test.dart; do
  echo "== $f"
  if out=$(flutter test "$f" -d linux 2>&1) && grep -q "All tests passed" <<<"$out"; then
    echo "All tests passed"
  else
    # The whole failure report (expectation, reason, stack), not just a summary.
    sed -n '/EXCEPTION CAUGHT/,$p' <<<"$out" | grep . || tail -n 40 <<<"$out"
    status=1
  fi
done
exit $status

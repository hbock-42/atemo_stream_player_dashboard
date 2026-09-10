#!/usr/bin/env bash
# Enforces the architecture mechanically, so the constraints survive a hurry.
# Run locally or in CI: tool/check_layers.sh
set -uo pipefail

fail=0
report() { echo "FAIL: $1"; fail=1; }

# --- ADR-0003: no Material, no Cupertino, anywhere ---------------------------
if grep -rn --include='*.dart' -E "package:flutter/(material|cupertino)\.dart" lib/ 2>/dev/null; then
  report "material.dart or cupertino.dart imported (ADR-0003)"
fi

# --- cast/ and domain/ stay pure Dart so the relay can run them ---------------
if grep -rn --include='*.dart' "package:flutter/" lib/cast/ lib/domain/ 2>/dev/null; then
  report "lib/cast/ or lib/domain/ imports Flutter (ADR-0002: the relay runs this code headless)"
fi

# --- the UI never learns the word Cast ---------------------------------------
if grep -rn --include='*.dart' -E "import .*(\.\./)+cast/" lib/ui/ 2>/dev/null; then
  report "lib/ui/ imports lib/cast/ — the UI must depend only on the domain seam"
fi

# --- ADR-0004: never evict the running session -------------------------------
# Quoted forms only, so prose about the rule doesn't trip the rule. Shipping
# code only: the relay's tests send LAUNCH deliberately, to prove the command
# envelope refuses it.
if grep -rn --include='*.dart' -E "['\"](LAUNCH|LOAD)['\"]" lib/ relay/lib/ relay/bin/ 2>/dev/null; then
  report "a LAUNCH or LOAD payload appears in the source (ADR-0004: it would evict the live session)"
fi

# --- commands live in exactly one file ---------------------------------------
offenders=$(grep -rln --include='*.dart' -E "['\"](PAUSE|QUEUE_NEXT|QUEUE_PREV|SET_VOLUME|SEEK)['\"]" lib/ 2>/dev/null \
  | grep -v 'lib/cast/cast_commands.dart' || true)
if [ -n "$offenders" ]; then
  report "command payloads outside lib/cast/cast_commands.dart:"
  echo "$offenders"
fi

# --- ADR-0005: the web build must never reach dart:io ------------------------
if grep -rn --include='*.dart' "dart:io" lib/ui/ lib/state/ 2>/dev/null; then
  report "dart:io reachable from lib/ui/ or lib/state/ — this breaks the web build (ADR-0005)"
fi

if [ "$fail" -eq 0 ]; then
  echo "Layer checks passed."
fi
exit "$fail"

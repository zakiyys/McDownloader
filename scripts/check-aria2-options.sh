#!/bin/bash
# Verify every aria2 command-line flag the app passes actually exists in the
# bundled aria2c build.
#
# Why this exists: the bundled aria2 is compiled with --disable-bittorrent, so
# every BitTorrent-only option is compiled out and becomes "unrecognized option"
# at runtime. aria2 then aborts at startup, the RPC port never opens, and the
# user sees "the download engine is not responding". This check turns that
# silent, packaging-time mistake into a loud CI failure.
#
# Usage: scripts/check-aria2-options.sh <path-to-aria2c> [path-to-Aria2Engine.swift]
set -euo pipefail

ARIA2="${1:?usage: check-aria2-options.sh <aria2c> [Aria2Engine.swift]}"
SRC="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/App/Sources/McDownloader/Engines/Aria2Engine.swift}"

[[ -x "$ARIA2" ]] || { echo "aria2c not executable: $ARIA2" >&2; exit 1; }
[[ -f "$SRC" ]] || { echo "source not found: $SRC" >&2; exit 1; }

# Every "--flag" literal the app builds (values are stripped, names compared).
mapfile -t flags < <(grep -oE '"--[a-z0-9-]+' "$SRC" | sed 's/"//' | sort -u)
[[ ${#flags[@]} -gt 0 ]] || { echo "no flags found in $SRC" >&2; exit 1; }

available="$("$ARIA2" --help=#all 2>&1 || true)"
[[ -n "$available" ]] || { echo "could not read options from $ARIA2" >&2; exit 1; }

fail=0
for f in "${flags[@]}"; do
  if grep -qF -- "$f" <<<"$available"; then
    echo "  ok    $f"
  else
    echo "  MISSING $f  (not compiled into this aria2 build)" >&2
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "" >&2
  echo "FAIL: the app passes options this aria2 build does not understand." >&2
  echo "aria2 aborts on an unknown option, which shows up as 'engine is not responding'." >&2
  exit 1
fi

echo "all ${#flags[@]} aria2 options are supported by $(basename "$ARIA2")"

#!/bin/bash
# Pre-task: ensure Finder is running and open a window on ~/Downloads.
#
# Finder is the macOS shell — it should already be running after install +
# setup. But the setup_finder.sh hook does a `killall Finder` for prefs
# flushing, so we re-confirm here. Idempotent.
set -eu

# Confirm Finder is alive. If somehow not, start it. launchd usually does
# this automatically.
if ! /usr/bin/pgrep -x Finder >/dev/null 2>&1; then
  echo "[pre_task] Finder not running — starting"
  /usr/bin/open -a Finder
fi

# Wait for Finder to register a process (it should already be running,
# but the prefs flush in setup_finder.sh may have just bounced it).
for i in $(seq 1 30); do
  if /usr/bin/pgrep -x Finder >/dev/null 2>&1; then
    echo "[pre_task] Finder process registered after ${i}s"
    break
  fi
  sleep 1
done

# Open a Finder window at ~/Downloads. `open <dir>` opens that directory in
# the current Finder (creates a window if none exists, brings existing
# window to front if one is on that path).
/usr/bin/open "$HOME/Downloads"

# Wait briefly for the window to appear via AppleEvents.
# osascript `tell application "Finder" to count windows` uses AppleEvents
# (Automation TCC, not Accessibility TCC) — Finder accepts AppleEvents
# from the SSH responsibility chain in practice, in contrast to System
# Events AX walks which don't. If it fails (zero or error), we just sleep
# and continue — the verifier handles the fallback.
for i in $(seq 1 15); do
  COUNT=$(osascript -e 'tell application "Finder" to count windows' 2>/dev/null || echo "0")
  if [ "${COUNT:-0}" -ge 1 ]; then
    echo "[pre_task] $COUNT Finder window(s) open after ${i}s"
    break
  fi
  sleep 1
done

# Force ~/Downloads into column view. The global `FXPreferredViewStyle=clmv`
# in setup_finder.sh applies to fresh folders the user hasn't visited, but
# ~/Downloads has a saved per-folder view that overrides it. Setting
# `current view of front window` via AppleEvent applies per-folder and
# persists in the folder's `.DS_Store`. AppleEvent to Finder works over SSH
# (Automation TCC). Surfaced in audit B1 (2026-05-18).
osascript -e 'tell application "Finder" to set current view of front window to column view' 2>/dev/null || true
sleep 1

# Brief settle for window chrome to lay out before screenshots.
sleep 2
echo "[pre_task] launch_finder ready"

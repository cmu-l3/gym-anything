#!/bin/bash
# Pre-task: launch Notion and wait for its window to register with
# LaunchServices. Idempotent — if already running, just wait. Mirrors the
# convention in 12_macos_environments.md (pre_task launches; agent operates
# inside).
set -eu

if ! pgrep -x "Notion" >/dev/null; then
  echo "[pre_task] launching Notion"
  # `open -a Notion` relies on LaunchServices having indexed the bundle.
  # Fall back to the absolute bundle path if name lookup fails (the
  # install hook does lsregister -f to avoid this in normal flow).
  if ! open -a "Notion" 2>/dev/null; then
    echo "[pre_task] 'open -a Notion' failed — falling back to bundle path"
    open /Applications/Notion.app
  fi
fi

# Poll lsappinfo until the Notion bundle has registered a window. Use a
# word-boundary grep so the count isn't inflated by helpers
# (`Notion Helper`, `Notion Helper (GPU)`, etc.) — see notes about Safari's
# helpers in specific_env_notes/safari/notes.md ("lsappinfo helpers" section).
for i in $(seq 1 45); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qiE '"Notion"( |$)'; then
    echo "[pre_task] Notion window registered after ${i}s"
    break
  fi
  sleep 1
done

# Brief settle so any startup animation / login-screen render reaches a stable
# state before screenshots / VNC viewer / agent step.
sleep 4

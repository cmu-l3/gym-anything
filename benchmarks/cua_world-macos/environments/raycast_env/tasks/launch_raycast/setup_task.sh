#!/bin/bash
# Pre-task: launch Raycast and wait for its process to register with
# LaunchServices. Idempotent \u2014 if already running, just wait. Mirrors the
# convention in 12_macos_environments.md (pre_task launches; agent operates
# inside).
#
# Note: `open -a Raycast` launches the menu-bar agent; Raycast on first launch
# also presents an onboarding window. Both states have process_running=true and
# a LaunchServices entry, so the smoke verifier passes either way.
set -eu

if ! pgrep -x "Raycast" >/dev/null; then
  echo "[pre_task] launching Raycast"
  # `open -a Raycast` relies on LaunchServices having indexed the bundle.
  # Fall back to the absolute bundle path if name lookup fails (the install
  # hook does lsregister -f to avoid this in normal flow).
  if ! open -a "Raycast" 2>/dev/null; then
    echo "[pre_task] 'open -a Raycast' failed \u2014 falling back to bundle path"
    open /Applications/Raycast.app
  fi
fi

# Poll lsappinfo until the Raycast bundle has registered with LaunchServices.
# Raycast does not have helper subprocesses like Notion/Safari, so the simple
# unquoted grep is sufficient \u2014 pgrep -x has already excluded any unrelated
# matches at the process layer.
for i in $(seq 1 45); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qE 'Raycast\.app'; then
    echo "[pre_task] Raycast registered with LaunchServices after ${i}s"
    break
  fi
  sleep 1
done

# Brief settle so any onboarding/launch animation reaches a stable state
# before screenshots / VNC viewer / agent step.
sleep 4

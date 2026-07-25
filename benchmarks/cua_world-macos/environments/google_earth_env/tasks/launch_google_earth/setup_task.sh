#!/bin/bash
# Pre-task: launch Google Earth Pro and wait for its window to register.
# Matches the cua_world google_earth convention (per
# extras/research/software_as_env/creation_audit/memory/.../google_earth/):
# tasks assume the app is already running; the agent performs actions
# inside it. Idempotent — if already running, just wait.
set -eu

if ! pgrep -f "Google Earth Pro" >/dev/null; then
  echo "[pre_task] launching Google Earth Pro"
  open -a "Google Earth Pro"
fi

# Poll lsappinfo until the bundle registers a window (or give up after ~30s).
for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qi "Google Earth"; then
    echo "[pre_task] Google Earth Pro window registered after ${i}s"
    break
  fi
  sleep 1
done

# Brief settle so startup dialogs reach their stable layout before any
# screenshot / VNC viewer / agent step.
sleep 3

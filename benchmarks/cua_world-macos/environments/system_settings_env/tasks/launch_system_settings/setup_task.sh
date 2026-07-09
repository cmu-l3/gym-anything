#!/bin/bash
# Pre-task: launch System Settings and wait for its window to register.
# Idempotent — if already running, just wait. Mirrors the convention in
# 12_macos_environments.md.
set -eu

if ! pgrep -x "System Settings" >/dev/null; then
  echo "[pre_task] launching System Settings"
  open -a "System Settings"
fi

# lsappinfo reports a `bundle path=".../System Settings.app"` line once
# LaunchServices has registered the window. Per the preview_env lesson
# (12_macos_environments.md "lsappinfo Regex"), match the bundle-path line
# instead of the process-name line — System Settings is a helper-free
# system app and `"System Settings"( |$)` won't match the lsappinfo entry
# (it's followed by a closing `"`, not space/EOL).
for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qiE 'System Settings\.app'; then
    echo "[pre_task] System Settings registered after ${i}s"
    break
  fi
  sleep 1
done

# Brief settle so the sidebar/title-bar chrome lays out before screenshots.
sleep 2

#!/bin/bash
# Pre-task: launch Pages, wait for window registration, then open a fresh
# blank document so the interactive viewer sees a usable editor rather than
# the Template Chooser. Idempotent.
#
# Why `make new document` and not just `open -a Pages`: on fresh launch Pages
# shows a modal Template Chooser ("Choose a Template" panel) covering the
# whole window. `tell application "Pages" to make new document` works over
# SSH (per 12_macos_environments.md \u2014 direct app scripting, not System
# Events) and bypasses the chooser by creating a blank document directly.
set -eu

if ! pgrep -x "Pages" >/dev/null; then
  echo "[pre_task] launching Pages"
  open -a Pages
fi

for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qF 'bundleID="com.apple.iWork.Pages"'; then
    echo "[pre_task] Pages window registered after ${i}s"
    break
  fi
  sleep 1
done

# Give the Template Chooser a moment to mount before AppleScript talks to
# the app \u2014 trying to `make new document` before the app is ready can
# return "AppleEvent timed out" sporadically.
sleep 2

# Open a blank document. If one is already open (idempotent re-runs), this
# just stacks a new window which is fine for the smoke task.
/usr/bin/osascript -e 'tell application "Pages" to make new document' 2>&1 || true

# Brief settle for the document window to lay out + the upgrade-alert
# suppressors to take effect before screenshots.
sleep 2

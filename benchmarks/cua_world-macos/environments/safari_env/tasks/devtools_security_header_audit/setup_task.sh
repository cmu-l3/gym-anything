#!/bin/bash
# pre_task hook for devtools_security_header_audit on Safari/macOS.
#
# Responsibilities:
#   1. Force-quit any prior Safari (so History.db starts clean for the
#      "visited after task start" check) and force the Web Inspector preference
#      to take effect (cfprefsd kill).
#   2. Delete any pre-existing report file so a do-nothing agent can't claim credit.
#   3. Record an authoritative task-start Unix timestamp.
#   4. Launch Safari with about:blank so the first navigation is verifiably the
#      agent's choice.
set -eu

echo "=== Setting up devtools_security_header_audit ==="

# 1) Clean slate for Safari + cfprefsd cache
osascript -e 'tell application "Safari" to quit' 2>/dev/null || true
sleep 2
pkill -x Safari 2>/dev/null || true
sleep 1

# Ensure the Web Inspector is reachable. (setup_safari.sh already wrote the
# pref + flushed cfprefsd, but we re-assert here so a single task's setup is
# self-contained and won't break if the env-level hook is ever rewritten.)
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari "WebKitPreferences.developerExtrasEnabled" -bool true
killall cfprefsd 2>/dev/null || true
sleep 1

# 2) Remove any stale report — anti-gaming. The verifier's freshness check
# (mtime > task_start) is the primary guard, but deleting up front is belt
# and suspenders and produces clearer feedback when an agent does nothing.
rm -f "$HOME/Documents/security_audit_report.json" 2>/dev/null || true
mkdir -p "$HOME/Documents"

# 3) Record task start (Unix epoch, seconds). The export script converts this
# to Mac absolute time (Unix - 978307200) when querying Safari's History.db.
date +%s > /tmp/task_start_timestamp
echo "task_start_unix=$(cat /tmp/task_start_timestamp)"

# 4) Launch Safari, wait for the window to register, then position on
# about:blank so the agent sees a known empty start state.
open -a Safari
for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qiE 'Safari( |$)'; then
    echo "Safari window registered after ${i}s"
    break
  fi
  sleep 1
done

# Navigate to about:blank deterministically.
osascript -e 'tell application "Safari" to make new document with properties {URL:"about:blank"}' 2>/dev/null || \
  open -a Safari "about:blank"

sleep 3

# Take a start-state screenshot for the trajectory archive.
/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

echo "=== devtools_security_header_audit setup complete ==="
echo "Safari is running with about:blank. Agent should open Web Inspector and audit security headers on 5 sites."

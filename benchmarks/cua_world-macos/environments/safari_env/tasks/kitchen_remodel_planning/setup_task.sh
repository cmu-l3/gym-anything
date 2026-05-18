#!/bin/bash
# setup_task.sh — kitchen_remodel_planning

set -euo pipefail

echo "=== Setting up kitchen_remodel_planning ==="

osascript -e 'tell application "Safari" to quit' 2>/dev/null || true
osascript -e 'tell application "Notes" to quit' 2>/dev/null || true
sleep 2

# Anti-gaming: delete pre-existing Notes related to this task
osascript << 'APPLEOF' 2>/dev/null || true
tell application "Notes"
    activate
    set toDelete to {}
    repeat with n in (get every note)
        set t to name of n as string
        if t contains "kitchen" or t contains "remodel" or t contains "renovation" or t contains "countertop" or t contains "cabinet" then
            set end of toDelete to n
        end if
    end repeat
    repeat with n in toDelete
        delete n
    end repeat
end tell
APPLEOF
sleep 1

osascript -e 'tell application "Notes" to quit' 2>/dev/null || true
sleep 1

defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari WebKitPreferences.developerExtrasEnabled -bool true
/usr/bin/killall cfprefsd 2>/dev/null || true
sleep 1

date +%s > /tmp/kitchen_remodel_planning_task_start_timestamp

open -a Safari "about:blank" 2>/dev/null || true
sleep 3

screencapture /tmp/kitchen_remodel_planning_start_screenshot.png 2>/dev/null || true

echo "=== Setup complete for kitchen_remodel_planning ==="

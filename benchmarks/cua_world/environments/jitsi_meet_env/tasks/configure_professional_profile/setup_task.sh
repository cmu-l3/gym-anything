#!/bin/bash
set -e
echo "=== Setting up Configure Professional Profile task ==="

source /workspace/scripts/task_utils.sh

# 1. timestamp
date +%s > /tmp/task_start_time.txt

# 2. Clear Firefox state to ensure no previous profile exists
echo "Clearing Firefox state..."
stop_firefox
rm -rf /home/ga/.mozilla/firefox/jitsi.profile/storage/default/http+++localhost+8080* 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/jitsi.profile/prefs.js 2>/dev/null || true

# 3. Start Firefox and navigate to the meeting URL
# We want the agent to start at the Pre-Join screen.
# Jitsi Meet shows Pre-Join by default for new users/rooms usually, 
# but we can enforce it via config in URL hash if needed, 
# though default behavior is usually sufficient if we haven't joined before.
TARGET_URL="http://localhost:8080/BoardMeetingQ4"

echo "Starting Firefox at $TARGET_URL..."
restart_firefox "$TARGET_URL" 10

# 4. Maximize and focus
maximize_firefox
focus_firefox

# 5. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
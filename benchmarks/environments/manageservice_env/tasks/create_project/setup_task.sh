#!/bin/bash
set -e
echo "=== Setting up create_project task ==="

# Source shared utilities for SDP interaction
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Ensure ServiceDesk Plus is running (waits for install if needed)
ensure_sdp_running

# 2. Clear mandatory password change so agent can log in smoothly
clear_mandatory_password_change

# 3. Record initial project count to detect changes
# Try multiple table names as schema versions vary
INITIAL_PROJECT_COUNT="0"
for table in "projecttab" "project" "projects"; do
    COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM $table;" 2>/dev/null || echo "")
    if [ -n "$COUNT" ]; then
        INITIAL_PROJECT_COUNT="$COUNT"
        echo "$table" > /tmp/project_table_name.txt
        break
    fi
done
echo "$INITIAL_PROJECT_COUNT" > /tmp/initial_project_count.txt
echo "Initial project count: $INITIAL_PROJECT_COUNT"

# 4. Launch Firefox to the Login Page
# Kill any existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox using the configured profile
su - ga -c "DISPLAY=:1 firefox --profile /home/ga/snap/firefox/common/.mozilla/firefox/sdp.profile 'https://localhost:8080' &" 2>/dev/null || \
su - ga -c "DISPLAY=:1 firefox 'https://localhost:8080' &" 2>/dev/null

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "firefox|mozilla"; then
        break
    fi
    sleep 1
done

# 5. Maximize and focus window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a :ACTIVE: 2>/dev/null || true

# Dismiss any startup dialogs (Esc key)
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
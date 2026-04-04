#!/bin/bash
set -e
echo "=== Setting up create_asset task ==="

# Source environment utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Ensure ServiceDesk Plus is running (waits for install if needed)
ensure_sdp_running

# 2. Clear mandatory password change to ensure smooth login
clear_mandatory_password_change

# 3. Record initial asset count to detect new creations
INITIAL_ASSET_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM Resources;" 2>/dev/null || echo "0")
echo "$INITIAL_ASSET_COUNT" > /tmp/initial_asset_count.txt
echo "Initial asset count: $INITIAL_ASSET_COUNT"

# 4. Launch Firefox to the login page
# Using the specific profile configured in post_start
log "Launching Firefox..."
pkill -f firefox 2>/dev/null || true
su - ga -c "DISPLAY=:1 firefox --profile /home/ga/snap/firefox/common/.mozilla/firefox/sdp.profile 'https://localhost:8080/ManageEngine/Login.do' &"

# 5. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Capture initial state screenshot
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
#!/bin/bash
set -e
echo "=== Setting up Configure Risk Notification task ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up any existing notifications that might conflict
# We delete notifications with similar names or logic to ensure we detect NEW work
echo "Cleaning up old notifications..."
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "DELETE FROM notifications WHERE name LIKE '%Risk Review%' OR name LIKE '%Upcoming Warning%';" 2>/dev/null || true

# 3. Ensure Firefox is running and logged in
# We start at the Dashboard to force the agent to find Settings
ensure_firefox_eramba "http://localhost:8080/dashboard/dashboard"

# 4. Maximize window for visibility
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
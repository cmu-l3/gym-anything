#!/bin/bash
set -e
echo "=== Setting up task: create_business_continuity_plan ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Record initial business continuity record count
# We use docker exec to query the database directly
INITIAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM business_continuities;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_bc_count.txt
echo "Initial business continuity record count: $INITIAL_COUNT"

# 3. Ensure Firefox is running and logged in
# We'll start at the dashboard to require navigation
ensure_firefox_eramba "http://localhost:8080/dashboard/dashboard"
sleep 5

# 4. Maximize window to ensure UI is visible
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 5. Take screenshot of initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot captured"

echo "=== Task setup complete ==="
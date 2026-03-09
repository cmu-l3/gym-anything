#!/bin/bash
echo "=== Setting up create_business_unit task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# 2. Record Initial Database State
# Count existing business units to ensure we can detect if a new one is added
INITIAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM business_units WHERE deleted=0;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial business units count: $INITIAL_COUNT"

# 3. Ensure Firefox is running and logged in
# We start at the Dashboard to test navigation to the 'Organization' section
ensure_firefox_eramba "http://localhost:8080/dashboard/dashboard"
sleep 5

# 4. Maximize window (Critical for VLM)
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 5. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
#!/bin/bash
echo "=== Setting up add_new_category task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
echo "task_start_ts=$(date +%s)" > /tmp/task_start_time.txt

# Ensure MariaDB is running
ensure_mariadb

# Make sure 'Seasonal Items' category does NOT exist (clean slate)
chromis_query "DELETE FROM CATEGORIES WHERE NAME='Seasonal Items'" 2>/dev/null || true

# Verify current category count
CAT_COUNT=$(chromis_query "SELECT COUNT(*) FROM CATEGORIES")
echo "Current categories: $CAT_COUNT"
chromis_query "SELECT NAME FROM CATEGORIES ORDER BY NAME"

# Kill any running Chromis instance
kill_chromis 2>/dev/null || true

# Launch Chromis POS
launch_chromis

# Wait for the window
wait_for_chromis 120

# Give the app time to fully load
sleep 15

# Dismiss any startup dialogs
dismiss_dialogs
sleep 3

# Try to log in (press Enter or click admin)
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return 2>/dev/null || true
sleep 3

# Focus and maximize the window
focus_chromis
maximize_chromis
sleep 2

# Take screenshot of the initial task state
take_screenshot /tmp/task_initial_state.png

echo "=== add_new_category task setup complete ==="
echo "Agent should see Chromis POS main screen."
echo "Agent needs to navigate to Stock/Maintenance > Categories and add 'Seasonal Items'"
echo "Current category count: $CAT_COUNT"

#!/bin/bash
set -e
echo "=== Setting up configure_work_week task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrangeHRM is running
wait_for_http "$ORANGEHRM_URL" 60

# ==============================================================================
# DATABASE PREPARATION
# Reset Work Week to standard: Mon-Fri = Full Day (0), Sat-Sun = Non-working (4)
# ==============================================================================
echo "Resetting Work Week configuration..."
# We assume the global work week is the row with id=1 or the only row
# Status codes: 0=Full, 4=Non-working (standard in recent OrangeHRM)
orangehrm_db_query "UPDATE ohrm_work_week SET mon=0, tue=0, wed=0, thu=0, fri=0, sat=4, sun=4 WHERE id=1;" 2>/dev/null || \
orangehrm_db_query "UPDATE ohrm_work_week SET mon=0, tue=0, wed=0, thu=0, fri=0, sat=4, sun=4;" 2>/dev/null

# Record initial state for verification
INITIAL_STATE=$(orangehrm_db_query "SELECT mon, tue, wed, thu, fri, sat, sun FROM ohrm_work_week LIMIT 1;" 2>/dev/null)
echo "$INITIAL_STATE" > /tmp/initial_work_week_state.txt
echo "Initial Work Week State (Mon-Sun): $INITIAL_STATE"

# ==============================================================================
# BROWSER SETUP
# ==============================================================================
# Navigate directly to the Work Week configuration page
# This helps the agent by putting them in the right context, though they still need to navigate the form
TARGET_URL="${ORANGEHRM_URL}/web/index.php/leave/defineWorkWeek"
ensure_orangehrm_logged_in "$TARGET_URL"

# Wait for page load
sleep 5

# Maximize window
maximize_active_window

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
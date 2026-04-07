#!/bin/bash
# Setup script for Generate Day Sheet Financial Report Task

echo "=== Setting up Generate Day Sheet Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
echo "Recording task start timestamp..."
date +%s > /tmp/task_start_time.txt
TASK_START=$(cat /tmp/task_start_time.txt)
echo "Task start timestamp: $TASK_START"

# Record initial audit log count to detect new activity
echo "Recording initial audit log state..."
INITIAL_LOG_COUNT=$(openemr_query "SELECT COUNT(*) FROM log" 2>/dev/null || echo "0")
echo "$INITIAL_LOG_COUNT" > /tmp/initial_log_count.txt
echo "Initial log entries: $INITIAL_LOG_COUNT"

# Record initial report-related log entries
INITIAL_REPORT_ACTIVITY=$(openemr_query "SELECT COUNT(*) FROM log WHERE event LIKE '%report%' OR comments LIKE '%report%'" 2>/dev/null || echo "0")
echo "$INITIAL_REPORT_ACTIVITY" > /tmp/initial_report_activity.txt
echo "Initial report-related log entries: $INITIAL_REPORT_ACTIVITY"

# Get today's date for reference
TODAY=$(date +%Y-%m-%d)
echo "$TODAY" > /tmp/task_date.txt
echo "Task date: $TODAY"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill any existing Firefox to start fresh
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Re-focus after maximize
    focus_window "$WID"
fi

# Dismiss any initial dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for audit verification
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Generate Day Sheet Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR"
echo "     - Username: admin"
echo "     - Password: pass"
echo ""
echo "  2. Navigate to Reports menu"
echo ""
echo "  3. Find Financial or Billing reports section"
echo ""
echo "  4. Select 'Day Sheet' or 'Daily Summary' report"
echo ""
echo "  5. Configure date to today ($TODAY) if needed"
echo ""
echo "  6. Generate/run the report"
echo ""
echo "  7. Verify the report displays transaction summaries"
echo ""
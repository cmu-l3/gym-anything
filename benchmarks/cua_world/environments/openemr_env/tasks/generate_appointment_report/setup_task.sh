#!/bin/bash
# Setup script for Generate Appointment Report task

echo "=== Setting up Generate Appointment Report Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Record current date info for verification
echo "$(date +%Y-%m-%d)" > /tmp/task_today_date.txt
echo "$(date -d "$(date +%Y-%m-01)" +%Y-%m-%d)" > /tmp/task_month_start.txt
echo "Today: $(cat /tmp/task_today_date.txt)"
echo "Month start: $(cat /tmp/task_month_start.txt)"

# Query initial appointment count (for context, not strict verification)
echo "Checking appointment data in database..."
APPT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events" 2>/dev/null || echo "0")
echo "$APPT_COUNT" > /tmp/initial_appt_count.txt
echo "Total appointments in system: $APPT_COUNT"

# Show a sample of appointments for debugging
echo ""
echo "=== Sample appointments in database ==="
openemr_query "SELECT pc_eid, pc_eventDate, pc_startTime, pc_pid, pc_title FROM openemr_postcalendar_events ORDER BY pc_eventDate DESC LIMIT 5" 2>/dev/null || echo "No appointments found"
echo "=== End sample ==="
echo ""

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill any existing Firefox instances for clean start
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox fresh
echo "Starting Firefox with OpenEMR..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window to appear
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected within timeout"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Focus again to ensure it's on top
    focus_window "$WID"
fi

# Dismiss any dialogs that might appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for audit
take_screenshot /tmp/task_initial.png
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Generate Appointment Report Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR (Username: admin, Password: pass)"
echo "  2. Navigate to Reports menu in top navigation"
echo "  3. Select an Appointments report"
echo "  4. Configure date range: 1st of current month to today"
echo "  5. Generate the report"
echo "  6. View the results"
echo ""
echo "Current month date range:"
echo "  From: $(cat /tmp/task_month_start.txt)"
echo "  To:   $(cat /tmp/task_today_date.txt)"
echo ""
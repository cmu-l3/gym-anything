#!/bin/bash
# Setup script for Generate HIPAA Audit Log Report Task

echo "=== Setting up Generate Audit Log Report Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=2
PATIENT_NAME="Rosa Bayer"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Generate some audit log entries by accessing this patient's record
# This ensures there will be entries to find in the report
echo "Generating audit log entries for patient..."

# Access patient demographics (creates log entry)
curl -s -b /tmp/openemr_cookies.txt -c /tmp/openemr_cookies.txt \
    "http://localhost/interface/patient_file/summary/demographics.php?set_pid=$PATIENT_PID" > /dev/null 2>&1 || true

sleep 1

# Record initial state - count of audit log entries for this patient
echo "Recording initial audit log state..."
INITIAL_LOG_COUNT=$(openemr_query "SELECT COUNT(*) FROM log WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_LOG_COUNT" > /tmp/initial_log_count.txt
echo "Initial log entries for patient: $INITIAL_LOG_COUNT"

# Also record total log entries
TOTAL_LOG_COUNT=$(openemr_query "SELECT COUNT(*) FROM log" 2>/dev/null || echo "0")
echo "$TOTAL_LOG_COUNT" > /tmp/total_log_count.txt
echo "Total log entries in system: $TOTAL_LOG_COUNT"

# Get date range for reference
TODAY=$(date +%Y-%m-%d)
THIRTY_DAYS_AGO=$(date -d "-30 days" +%Y-%m-%d)
echo "Valid date range: $THIRTY_DAYS_AGO to $TODAY"
echo "$TODAY" > /tmp/date_today.txt
echo "$THIRTY_DAYS_AGO" > /tmp/date_30_days_ago.txt

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill existing Firefox to start fresh
pkill -f firefox 2>/dev/null || true
sleep 2

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
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Dismiss any popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot
echo "Capturing initial screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Generate Audit Log Report Task Setup Complete ==="
echo ""
echo "TASK: Generate HIPAA Audit Log Report"
echo "======================================"
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 2015-10-10)"
echo "Date Range: Past 30 days ($THIRTY_DAYS_AGO to $TODAY)"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (admin/pass)"
echo "  2. Navigate to Reports > Audit Log (or Administration > Audit Log)"
echo "  3. Filter by patient: Rosa Bayer (PID 2)"
echo "  4. Set date range: past 30 days"
echo "  5. Generate/view the filtered report"
echo ""
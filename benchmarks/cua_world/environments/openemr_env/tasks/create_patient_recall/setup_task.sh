#!/bin/bash
# Setup script for Create Patient Recall Task

echo "=== Setting up Create Patient Recall Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial recall/reminder count for this patient
# OpenEMR may use different tables for recalls - check multiple possibilities
echo "Recording initial recall counts..."

# Check patient_reminders table (common in OpenEMR)
INITIAL_REMINDERS=$(openemr_query "SELECT COUNT(*) FROM patient_reminders WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_REMINDERS" > /tmp/initial_reminder_count.txt
echo "Initial patient_reminders count: $INITIAL_REMINDERS"

# Check if there's a recall-specific table
INITIAL_RECALLS=$(openemr_query "SELECT COUNT(*) FROM patient_recall WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_RECALLS" > /tmp/initial_recall_count.txt
echo "Initial patient_recall count: $INITIAL_RECALLS"

# Also check calendar events that might be used for recalls
INITIAL_CALENDAR=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eventDate > CURDATE()" 2>/dev/null || echo "0")
echo "$INITIAL_CALENDAR" > /tmp/initial_calendar_count.txt
echo "Initial future calendar events: $INITIAL_CALENDAR"

# Get list of existing reminder IDs for this patient (to detect new ones)
EXISTING_REMINDER_IDS=$(openemr_query "SELECT id FROM patient_reminders WHERE pid=$PATIENT_PID ORDER BY id" 2>/dev/null || echo "")
echo "$EXISTING_REMINDER_IDS" > /tmp/existing_reminder_ids.txt

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

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

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Create Patient Recall Task Setup Complete ==="
echo ""
echo "Task: Create a patient recall entry for preventive care"
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Recall Reason: Annual Wellness Exam"
echo "Recall Date: Approximately 6 months from today"
echo ""
echo "Navigation hints:"
echo "  - Patient > Recall Board"
echo "  - Reports > Patient Reminders"
echo "  - Miscellaneous > Patient Reminders"
echo ""
#!/bin/bash
# Setup task: schedule_appointment
# Patient: Coreen Treutel (ID 14) - Synthea-generated patient

echo "=== Setting up schedule_appointment task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Verify patient Coreen Treutel (ID 14)
PATIENT=$(freemed_query "SELECT id, ptfname, ptlname FROM patient WHERE id=14" 2>/dev/null)
echo "Target patient: $PATIENT"

if [ -z "$PATIENT" ]; then
    echo "ERROR: Patient ID 14 (Coreen Treutel) not found!"
    exit 1
fi

# Remove any existing appointment for Coreen on 2025-06-20 (clean state)
freemed_query "DELETE FROM scheduler WHERE calpatient=14 AND caldateof='2025-06-20'" 2>/dev/null || true

# Record initial appointment count
INITIAL=$(freemed_query "SELECT COUNT(*) FROM scheduler WHERE calpatient=14" 2>/dev/null || echo "0")
echo "$INITIAL" > /tmp/initial_appointment_count
echo "Initial appointment count for Coreen: $INITIAL"

ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_schedule_start.png

echo ""
echo "=== schedule_appointment task setup complete ==="
echo "Task: Schedule appointment for Coreen Treutel (ID=14)"
echo "Date: 2025-06-20, Time: 09:00 AM, Duration: 30 min, Type: Office Visit"
echo "Login: admin / admin"
echo ""

#!/bin/bash
echo "=== Setting up export_patient_roster_pdf task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure clean state: delete any existing target file
TARGET_FILE="/home/ga/Documents/patient_roster.pdf"
rm -f "$TARGET_FILE" 2>/dev/null || true

# Check if we have patients in the DB
PATIENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM patient" 2>/dev/null || echo "0")
echo "Current patient count in DB: $PATIENT_COUNT"

# Ensure Firefox is running and navigated to FreeMED
echo "Ensuring Firefox is running..."
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Target: $TARGET_FILE"
echo "Instructions: Log in, navigate to patient list, use browser Print to PDF, save to target location."
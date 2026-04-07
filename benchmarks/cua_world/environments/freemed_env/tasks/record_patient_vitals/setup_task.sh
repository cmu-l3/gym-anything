#!/bin/bash
# Setup script for Record Patient Vitals task

echo "=== Setting up Record Patient Vitals Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Ensure patient "Maria Santos" exists in the DB
echo "Verifying patient exists in database..."
EXISTS=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='Maria' AND ptlname='Santos'" 2>/dev/null || echo "0")

if [ "$EXISTS" -eq "0" ]; then
    echo "Patient Maria Santos not found. Injecting patient record..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex) VALUES ('Maria', 'Santos', '1973-05-10', 'Female')" 2>/dev/null || true
fi

# 2. Get the patient ID
PID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Maria' AND ptlname='Santos' LIMIT 1" 2>/dev/null)
if [ -z "$PID" ]; then
    echo "ERROR: Failed to retrieve or create target patient."
    exit 1
fi
echo "$PID" > /tmp/target_patient_id.txt
echo "Target Patient ID: $PID"

# 3. Find the correct column name for patient ID in vitals table
PAT_COL=$(mysql -u freemed -pfreemed freemed -N -B -e "SHOW COLUMNS FROM vitals" 2>/dev/null | grep -iE "^(patient|vpatient|ppatient)" | head -1 | awk '{print $1}')
[ -z "$PAT_COL" ] && PAT_COL="patient"

# 4. Record the initial vitals count for this patient
INITIAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM vitals WHERE $PAT_COL=$PID" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_vitals_count.txt
echo "Initial vitals count for patient: $INITIAL_COUNT"

# 5. Ensure Firefox is running and at FreeMED login
echo "Starting application environment..."
ensure_firefox_running "http://localhost/freemed/"

# Maximize and Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Record vitals for Maria Santos"
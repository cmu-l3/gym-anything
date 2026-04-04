#!/bin/bash
# Setup task: record_vital_signs
# Patient: Tracey Crona (ID 15) - Synthea-generated patient
# Real vitals from Synthea 2023-10-19 encounter: BP 119/73, HR 70, weight 72.7kg

echo "=== Setting up record_vital_signs task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Verify patient Tracey Crona (ID 15)
PATIENT=$(freemed_query "SELECT id, ptfname, ptlname FROM patient WHERE id=15" 2>/dev/null)
echo "Target patient: $PATIENT"

if [ -z "$PATIENT" ]; then
    echo "ERROR: Patient ID 15 (Tracey Crona) not found!"
    exit 1
fi

# Record initial vital signs count for this patient
INITIAL=$(freemed_query "SELECT COUNT(*) FROM vitals WHERE patient=15" 2>/dev/null || echo "0")
echo "$INITIAL" > /tmp/initial_vitals_count
echo "Initial vitals count for Tracey: $INITIAL"

ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_vitals_start.png

echo ""
echo "=== record_vital_signs task setup complete ==="
echo "Task: Record BP 119/73, HR 70, Temp 98.4F, Wt 160lbs, Ht 61in for Tracey Crona (ID=15)"
echo "Login: admin / admin"
echo ""

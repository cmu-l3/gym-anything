#!/bin/bash
echo "=== Setting up record_surgical_history task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Ensure patient Thomas Anderson exists
echo "Checking for patient Thomas Anderson..."
EXISTS=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='Thomas' AND ptlname='Anderson'")

if [ "$EXISTS" -eq "0" ]; then
    echo "Creating patient Thomas Anderson..."
    # Insert basic demographic data so the patient is searchable
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex) VALUES ('Thomas', 'Anderson', '1980-03-11', 1);"
fi

# Get Patient ID
PATIENT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Thomas' AND ptlname='Anderson' LIMIT 1")
echo "Target patient ID: $PATIENT_ID"

if [ -z "$PATIENT_ID" ]; then
    echo "ERROR: Failed to establish target patient."
    exit 1
fi

# Clean up any pre-existing cholecystectomy entries for this patient to ensure a clean state
echo "Cleaning up any existing surgical history for this task..."
# We run a cleanup using a safe mysql wildcard deletion on typical surgical tables if they exist
freemed_query "DELETE FROM surgeries WHERE patient=$PATIENT_ID;" 2>/dev/null || true
freemed_query "DELETE FROM surgicalhistory WHERE patient=$PATIENT_ID;" 2>/dev/null || true
freemed_query "DELETE FROM hx_surgery WHERE patient=$PATIENT_ID;" 2>/dev/null || true

# Start Firefox and navigate to FreeMED dashboard
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize the window
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any leftover dialogs
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape
fi

# Take initial screenshot showing starting state
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="
echo "Target: Thomas Anderson (ID: $PATIENT_ID)"
echo "Procedure: Laparoscopic Cholecystectomy"
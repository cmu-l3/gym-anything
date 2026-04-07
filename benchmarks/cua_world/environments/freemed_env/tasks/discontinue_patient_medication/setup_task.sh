#!/bin/bash
echo "=== Setting up discontinue_patient_medication task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Ensure patient Marcus Johnson exists
PID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Marcus' AND ptlname='Johnson' LIMIT 1" 2>/dev/null)
if [ -z "$PID" ]; then
    echo "Creating patient Marcus Johnson..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob) VALUES ('Marcus', 'Johnson', '1975-04-12')" 2>/dev/null
    PID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Marcus' AND ptlname='Johnson' LIMIT 1" 2>/dev/null)
fi

echo "Patient ID: $PID"

# 2. Clear any existing prescriptions for this patient to ensure a clean state
freemed_query "DELETE FROM rx WHERE rxpatient='$PID'" 2>/dev/null

# 3. Insert the target prescription (Atorvastatin)
freemed_query "INSERT INTO rx (rxpatient, rxdrug, rxnote) VALUES ('$PID', 'Atorvastatin 40mg', 'Take 1 tablet daily at bedtime for hyperlipidemia')" 2>/dev/null
TARGET_ID=$(freemed_query "SELECT id FROM rx WHERE rxpatient='$PID' AND rxdrug LIKE '%Atorvastatin%' LIMIT 1" 2>/dev/null)

# 4. Insert the distractor prescription (Lisinopril)
freemed_query "INSERT INTO rx (rxpatient, rxdrug, rxnote) VALUES ('$PID', 'Lisinopril 10mg', 'Take 1 tablet daily for hypertension')" 2>/dev/null
DISTRACTOR_ID=$(freemed_query "SELECT id FROM rx WHERE rxpatient='$PID' AND rxdrug LIKE '%Lisinopril%' LIMIT 1" 2>/dev/null)

echo "Target Rx ID: $TARGET_ID, Distractor Rx ID: $DISTRACTOR_ID"

# Save these IDs for the export script
cat > /tmp/initial_rx.json << EOF
{
    "patient_id": "$PID",
    "target_id": "$TARGET_ID",
    "distractor_id": "$DISTRACTOR_ID",
    "distractor_initial_note": "Take 1 tablet daily for hypertension"
}
EOF

# 5. Ensure Firefox is running and focused on FreeMED
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize the window
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
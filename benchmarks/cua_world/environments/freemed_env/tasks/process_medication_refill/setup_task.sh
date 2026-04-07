#!/bin/bash
# Setup script for Process Medication Refill task

echo "=== Setting up process_medication_refill task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create patient Robert Jenkins if not exists
EXISTING_PID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Robert' AND ptlname='Jenkins' LIMIT 1" 2>/dev/null)
if [ -z "$EXISTING_PID" ]; then
    echo "Creating patient Robert Jenkins..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex, ptaddr1, ptcity, ptstate, ptzip, pthphone) VALUES ('Robert', 'Jenkins', '1962-04-12', 1, '123 Main St', 'Springfield', 'IL', '62701', '555-0199')" 2>/dev/null
    PID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Robert' AND ptlname='Jenkins' LIMIT 1" 2>/dev/null)
else
    echo "Patient Robert Jenkins already exists (ID: $EXISTING_PID)"
    PID="$EXISTING_PID"
fi

echo "Patient ID: $PID"
echo "$PID" > /tmp/patient_id.txt

# 2. Clear any existing prescriptions for this patient to ensure a clean state
freemed_query "DELETE FROM rx WHERE rxpatient=$PID" 2>/dev/null

# 3. Insert the 3 required prescriptions with 0 refills
echo "Injecting baseline prescriptions (0 refills)..."
freemed_query "INSERT INTO rx (rxpatient, rxdrug, rxquantity, rxrefills, rxdate) VALUES ($PID, 'Atorvastatin 40mg Oral Tablet', '30', '0', '2024-12-01')" 2>/dev/null
freemed_query "INSERT INTO rx (rxpatient, rxdrug, rxquantity, rxrefills, rxdate) VALUES ($PID, 'Metformin 500mg Oral Tablet', '90', '0', '2024-12-01')" 2>/dev/null
freemed_query "INSERT INTO rx (rxpatient, rxdrug, rxquantity, rxrefills, rxdate) VALUES ($PID, 'Lisinopril 10mg Oral Tablet', '30', '0', '2024-12-01')" 2>/dev/null

# 4. Ensure Firefox is running and focused
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize the window for better agent interaction
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
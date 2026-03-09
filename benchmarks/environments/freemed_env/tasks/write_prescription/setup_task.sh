#!/bin/bash
# Setup task: write_prescription
# Patient: Crystal Schroeder (ID 18) - Synthea-generated patient
# Synthea data: Naproxen sodium 220 MG Oral Tablet prescribed 2024-02-10

echo "=== Setting up write_prescription task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Verify patient Crystal Schroeder (ID 18)
PATIENT=$(freemed_query "SELECT id, ptfname, ptlname FROM patient WHERE id=18" 2>/dev/null)
echo "Target patient: $PATIENT"

if [ -z "$PATIENT" ]; then
    echo "ERROR: Patient ID 18 (Crystal Schroeder) not found!"
    exit 1
fi

# Remove any pre-existing Naproxen entries for clean state
freemed_query "DELETE FROM medications WHERE mpatient=18 AND mdrugs LIKE '%Naproxen%'" 2>/dev/null || true

# Record initial medication count
INITIAL=$(freemed_query "SELECT COUNT(*) FROM medications WHERE mpatient=18" 2>/dev/null || echo "0")
echo "$INITIAL" > /tmp/initial_medication_count
echo "Initial medication count for Crystal: $INITIAL"

ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_prescription_start.png

echo ""
echo "=== write_prescription task setup complete ==="
echo "Task: Write Naproxen Sodium 220mg prescription for Crystal Schroeder (ID=18)"
echo "Qty: 30 tablets, 1 tablet twice daily as needed, 0 refills"
echo "Login: admin / admin"
echo ""

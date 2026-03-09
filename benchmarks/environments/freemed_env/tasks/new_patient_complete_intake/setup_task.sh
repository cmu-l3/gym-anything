#!/bin/bash
# Setup task: new_patient_complete_intake
# New patient: Helena Vasquez (DOB 1978-08-14, F) — must NOT exist at task start

echo "=== Setting up new_patient_complete_intake ==="

source /workspace/scripts/task_utils.sh

# Ensure Helena Vasquez does NOT exist in the database (clean state)
freemed_query "DELETE FROM medications WHERE mpatient IN (SELECT id FROM patient WHERE ptfname='Helena' AND ptlname='Vasquez')" 2>/dev/null || true
freemed_query "DELETE FROM current_problems WHERE ppatient IN (SELECT id FROM patient WHERE ptfname='Helena' AND ptlname='Vasquez')" 2>/dev/null || true
freemed_query "DELETE FROM allergies_atomic WHERE patient IN (SELECT id FROM patient WHERE ptfname='Helena' AND ptlname='Vasquez')" 2>/dev/null || true
freemed_query "DELETE FROM allergies WHERE patient IN (SELECT id FROM patient WHERE ptfname='Helena' AND ptlname='Vasquez')" 2>/dev/null || true
freemed_query "DELETE FROM pnotes WHERE pnotespat IN (SELECT id FROM patient WHERE ptfname='Helena' AND ptlname='Vasquez')" 2>/dev/null || true
freemed_query "DELETE FROM patient WHERE ptfname='Helena' AND ptlname='Vasquez'" 2>/dev/null || true

# Verify patient does not exist
PATIENT_CHECK=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='Helena' AND ptlname='Vasquez'" 2>/dev/null || echo "0")
echo "Helena Vasquez count after cleanup: $PATIENT_CHECK"

if [ "${PATIENT_CHECK:-0}" -gt 0 ]; then
    echo "ERROR: Could not remove existing Helena Vasquez entries!"
    exit 1
fi

# Record initial patient count (baseline)
INITIAL_PATIENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM patient" 2>/dev/null || echo "0")
echo "$INITIAL_PATIENT_COUNT" > /tmp/npci_initial_patient_count

echo "Initial patient count: $INITIAL_PATIENT_COUNT"
echo "Setup: Helena Vasquez does not exist. Agent must register her and complete her chart."

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch FreeMED
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/new_patient_complete_intake_start.png

echo ""
echo "=== Setup Complete ==="
echo "New patient: Helena Vasquez (DOB: 1978-08-14, Female)"
echo "Agent must: register patient + add 2 diagnoses + Metformin Rx + Sulfonamides allergy"
echo "Login: admin / admin at http://localhost/freemed/"
echo ""

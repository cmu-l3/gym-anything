#!/bin/bash
# Setup task: preventive_care_protocol
# Patient: Sherill Botsford (ID 10, DOB 1995-01-24, F)
# Task: Full preventive visit — vitals + 2 immunizations + note + follow-up appointment

echo "=== Setting up preventive_care_protocol ==="

source /workspace/scripts/task_utils.sh

PATIENT_ID=10

# Verify target patient exists
PATIENT=$(freemed_query "SELECT id, ptfname, ptlname FROM patient WHERE id=$PATIENT_ID" 2>/dev/null)
echo "Target patient: $PATIENT"

if [ -z "$PATIENT" ]; then
    echo "ERROR: Patient ID $PATIENT_ID (Sherill Botsford) not found!"
    exit 1
fi

# Clear pre-existing data for clean, deterministic state
freemed_query "DELETE FROM vitals WHERE patient=$PATIENT_ID" 2>/dev/null || true
freemed_query "DELETE FROM immunization WHERE patient=$PATIENT_ID AND (vaccine LIKE '%Tdap%' OR vaccine LIKE '%Td%' OR vaccine LIKE '%Influenza%' OR vaccine LIKE '%Flu%')" 2>/dev/null || true
freemed_query "DELETE FROM pnotes WHERE pnotespat=$PATIENT_ID" 2>/dev/null || true
freemed_query "DELETE FROM scheduler WHERE calpatient=$PATIENT_ID AND caldateof='2026-03-01'" 2>/dev/null || true

echo "Cleared pre-existing data for patient $PATIENT_ID"

# Record initial counts
INITIAL_VITALS=$(freemed_query "SELECT COUNT(*) FROM vitals WHERE patient=$PATIENT_ID" 2>/dev/null || echo "0")
INITIAL_IMMUNIZATIONS=$(freemed_query "SELECT COUNT(*) FROM immunization WHERE patient=$PATIENT_ID" 2>/dev/null || echo "0")
INITIAL_NOTES=$(freemed_query "SELECT COUNT(*) FROM pnotes WHERE pnotespat=$PATIENT_ID" 2>/dev/null || echo "0")
INITIAL_APPOINTMENTS=$(freemed_query "SELECT COUNT(*) FROM scheduler WHERE calpatient=$PATIENT_ID" 2>/dev/null || echo "0")

echo "$INITIAL_VITALS" > /tmp/pcp_initial_vitals
echo "$INITIAL_IMMUNIZATIONS" > /tmp/pcp_initial_immunizations
echo "$INITIAL_NOTES" > /tmp/pcp_initial_notes
echo "$INITIAL_APPOINTMENTS" > /tmp/pcp_initial_appointments

echo "Initial counts — vitals: $INITIAL_VITALS, immunizations: $INITIAL_IMMUNIZATIONS, notes: $INITIAL_NOTES, appointments: $INITIAL_APPOINTMENTS"

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
take_screenshot /tmp/preventive_care_protocol_start.png

echo ""
echo "=== Setup Complete ==="
echo "Patient: Sherill Botsford (ID=$PATIENT_ID, DOB: 1995-01-24)"
echo "Task: Record vitals + Tdap + Influenza vaccines + preventive note + schedule 2026-03-01"
echo "Login: admin / admin at http://localhost/freemed/"
echo ""

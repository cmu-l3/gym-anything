#!/bin/bash
# Setup task: complex_chronic_disease_visit
# Patient: Dwight Dach (ID 6, DOB 1998-03-21, M)
# Task: Document complex chronic disease visit (2 diagnoses + vitals + Rx + note)

echo "=== Setting up complex_chronic_disease_visit ==="

source /workspace/scripts/task_utils.sh

PATIENT_ID=6

# Verify target patient exists
PATIENT=$(freemed_query "SELECT id, ptfname, ptlname FROM patient WHERE id=$PATIENT_ID" 2>/dev/null)
echo "Target patient: $PATIENT"

if [ -z "$PATIENT" ]; then
    echo "ERROR: Patient ID $PATIENT_ID (Dwight Dach) not found in database!"
    exit 1
fi

# Clear any pre-existing data for this task to ensure deterministic state
freemed_query "DELETE FROM current_problems WHERE ppatient=$PATIENT_ID AND (problem_code='401.9' OR problem_code='790.29')" 2>/dev/null || true
freemed_query "DELETE FROM vitals WHERE patient=$PATIENT_ID" 2>/dev/null || true
freemed_query "DELETE FROM medications WHERE mpatient=$PATIENT_ID AND mdrugs LIKE '%Lisinopril%'" 2>/dev/null || true
freemed_query "DELETE FROM pnotes WHERE pnotespat=$PATIENT_ID" 2>/dev/null || true

echo "Cleared pre-existing data for patient $PATIENT_ID"

# Record initial counts (all should be 0 after cleanup)
INITIAL_PROBLEMS=$(freemed_query "SELECT COUNT(*) FROM current_problems WHERE ppatient=$PATIENT_ID" 2>/dev/null || echo "0")
INITIAL_VITALS=$(freemed_query "SELECT COUNT(*) FROM vitals WHERE patient=$PATIENT_ID" 2>/dev/null || echo "0")
INITIAL_MEDS=$(freemed_query "SELECT COUNT(*) FROM medications WHERE mpatient=$PATIENT_ID" 2>/dev/null || echo "0")
INITIAL_NOTES=$(freemed_query "SELECT COUNT(*) FROM pnotes WHERE pnotespat=$PATIENT_ID" 2>/dev/null || echo "0")

echo "$INITIAL_PROBLEMS" > /tmp/ccdv_initial_problems
echo "$INITIAL_VITALS" > /tmp/ccdv_initial_vitals
echo "$INITIAL_MEDS" > /tmp/ccdv_initial_meds
echo "$INITIAL_NOTES" > /tmp/ccdv_initial_notes

echo "Initial counts — problems: $INITIAL_PROBLEMS, vitals: $INITIAL_VITALS, meds: $INITIAL_MEDS, notes: $INITIAL_NOTES"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure FreeMED is running and accessible
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/complex_chronic_disease_visit_start.png

echo ""
echo "=== Setup Complete ==="
echo "Patient: Dwight Dach (ID=$PATIENT_ID, DOB: 1998-03-21)"
echo "Task: Document hypertension (401.9) + prediabetes (790.29) + vitals + Lisinopril Rx + note"
echo "Login: admin / admin at http://localhost/freemed/"
echo ""

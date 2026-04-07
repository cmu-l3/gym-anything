#!/bin/bash
# Setup script for Document Medication Administration Task

echo "=== Setting up Document Medication Administration Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_timestamp
TASK_START=$(cat /tmp/task_start_timestamp)
echo "Task start timestamp: $TASK_START"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial immunization count for this patient
echo "Recording initial immunization count..."
INITIAL_IMM_COUNT=$(openemr_query "SELECT COUNT(*) FROM immunizations WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_IMM_COUNT" > /tmp/initial_immunization_count
echo "Initial immunization count for patient: $INITIAL_IMM_COUNT"

# Record initial forms count for this patient
INITIAL_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_FORMS_COUNT" > /tmp/initial_forms_count
echo "Initial forms count for patient: $INITIAL_FORMS_COUNT"

# Get list of existing immunization IDs to identify new ones
openemr_query "SELECT id FROM immunizations WHERE patient_id=$PATIENT_PID ORDER BY id" 2>/dev/null > /tmp/initial_immunization_ids
echo "Recorded existing immunization IDs"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for audit
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved"

echo ""
echo "=== Document Medication Administration Task Setup Complete ==="
echo ""
echo "Task: Document that a vitamin B12 injection was administered"
echo ""
echo "Patient: $PATIENT_NAME (DOB: 1992-06-30)"
echo ""
echo "Details to document:"
echo "  - Medication: Cyanocobalamin (Vitamin B12)"
echo "  - Dose: 1000 mcg"
echo "  - Route: Intramuscular (IM)"
echo "  - Site: Left deltoid"
echo ""
echo "Login credentials: admin / pass"
echo ""
echo "Navigate to: Patient > Medical Record > Immunizations"
echo "             OR Patient > Encounter > Add Immunization"
echo ""
#!/bin/bash
# Setup: admit_patient task
# Ensures James Smith exists in the system and opens Firefox on Care2x.

echo "=== Setting up admit_patient task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# Verify that James Smith exists in the database
echo "Checking for patient James Smith..."
PATIENT_PID=$(get_patient_pid "James" "Smith")
if [ -z "$PATIENT_PID" ]; then
    echo "ERROR: Patient James Smith not found in database!"
    exit 1
fi
echo "Patient PID: $PATIENT_PID"

# Remove any existing admission for this patient to allow re-runs
echo "Clearing any existing admissions for James Smith..."
care2x_query "DELETE FROM care_encounter WHERE pid='$PATIENT_PID';" 2>/dev/null || true

# Open Firefox on Care2x
ensure_firefox_on_url "$CARE2X_URL"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== admit_patient task setup complete ==="
echo ""
echo "TASK: Admit patient James Smith"
echo "  Patient:    James Smith (PID: $PATIENT_PID)"
echo "  Department: Internal Medicine"
echo ""
echo "Login: admin / care2x_admin"

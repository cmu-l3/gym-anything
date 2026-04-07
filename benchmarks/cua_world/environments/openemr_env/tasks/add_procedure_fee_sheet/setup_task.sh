#!/bin/bash
# Setup script for Add Procedure to Fee Sheet task

echo "=== Setting up Add Procedure to Fee Sheet Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=5
PATIENT_FNAME="Gerald"
PATIENT_LNAME="Koss"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_FNAME $PATIENT_LNAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient Gerald Koss (pid=5) not found in database!"
    echo "Available patients:"
    openemr_query "SELECT pid, fname, lname FROM patient_data LIMIT 10" 2>/dev/null
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Check for existing encounters for this patient
ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Existing encounters for patient: $ENCOUNTER_COUNT"

# If no encounters exist, create one for the task
if [ "$ENCOUNTER_COUNT" -lt 1 ]; then
    echo "No encounters found. Creating an encounter for the patient..."
    
    # Get the next encounter number
    NEXT_ENCOUNTER=$(openemr_query "SELECT IFNULL(MAX(encounter),0)+1 FROM form_encounter" 2>/dev/null || echo "1")
    
    # Create an encounter
    openemr_query "INSERT INTO form_encounter (date, reason, pid, encounter, facility_id, provider_id, sensitivity, pc_catid) VALUES (CURDATE(), 'Routine follow-up visit', $PATIENT_PID, $NEXT_ENCOUNTER, 3, 1, 'normal', 5)" 2>/dev/null
    
    # Also need to create the forms entry
    openemr_query "INSERT INTO forms (date, encounter, form_name, form_id, pid, user, groupname, authorized, formdir) VALUES (NOW(), $NEXT_ENCOUNTER, 'New Patient Encounter', $NEXT_ENCOUNTER, $PATIENT_PID, 'admin', 'Default', 1, 'newpatient')" 2>/dev/null
    
    ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
    echo "Created encounter. New encounter count: $ENCOUNTER_COUNT"
fi

# Get the most recent encounter ID for this patient
LATEST_ENCOUNTER=$(openemr_query "SELECT encounter FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY date DESC, id DESC LIMIT 1" 2>/dev/null)
echo "Most recent encounter ID: $LATEST_ENCOUNTER"
echo "$LATEST_ENCOUNTER" > /tmp/patient_encounter_id.txt

# Record initial billing count for this patient with code 99213
INITIAL_BILLING_COUNT=$(openemr_query "SELECT COUNT(*) FROM billing WHERE pid=$PATIENT_PID AND code='99213'" 2>/dev/null || echo "0")
echo "$INITIAL_BILLING_COUNT" > /tmp/initial_billing_count.txt
echo "Initial billing entries with code 99213 for patient: $INITIAL_BILLING_COUNT"

# Record total billing count for patient
INITIAL_TOTAL_BILLING=$(openemr_query "SELECT COUNT(*) FROM billing WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_TOTAL_BILLING" > /tmp/initial_total_billing.txt
echo "Initial total billing entries for patient: $INITIAL_TOTAL_BILLING"

# Show existing billing entries for debugging
echo ""
echo "=== Existing billing entries for patient ==="
openemr_query "SELECT id, date, code_type, code, encounter, activity FROM billing WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null || echo "None"
echo ""

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

# Take initial screenshot for audit verification
sleep 1
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Add Procedure to Fee Sheet Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_FNAME $PATIENT_LNAME (PID: $PATIENT_PID)"
echo "DOB: 1965-10-22"
echo "Encounter ID: $LATEST_ENCOUNTER"
echo ""
echo "Task: Add CPT code 99213 to the fee sheet for this patient's encounter"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (admin/pass)"
echo "  2. Search for patient 'Gerald Koss'"
echo "  3. Open the patient's chart"
echo "  4. Navigate to an existing encounter"
echo "  5. Go to Fees > Fee Sheet"
echo "  6. Add code: Type=CPT4, Code=99213"
echo "  7. Save the fee sheet"
echo ""
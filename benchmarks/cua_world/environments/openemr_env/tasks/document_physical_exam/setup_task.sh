#!/bin/bash
# Setup script for Document Physical Exam task

echo "=== Setting up Document Physical Exam Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
TASK_START=$(cat /tmp/task_start_time.txt)
echo "Task start timestamp: $TASK_START"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Check for existing encounter today, create if needed
echo "Checking for today's encounter..."
TODAY=$(date +%Y-%m-%d)
EXISTING_ENCOUNTER=$(openemr_query "SELECT encounter FROM form_encounter WHERE pid=$PATIENT_PID AND DATE(date)='$TODAY' ORDER BY encounter DESC LIMIT 1" 2>/dev/null)

if [ -z "$EXISTING_ENCOUNTER" ]; then
    echo "Creating new encounter for today..."
    # Get max encounter ID
    MAX_ENCOUNTER=$(openemr_query "SELECT COALESCE(MAX(encounter),0) FROM form_encounter" 2>/dev/null || echo "0")
    NEW_ENCOUNTER=$((MAX_ENCOUNTER + 1))
    
    # Insert new encounter
    openemr_query "INSERT INTO form_encounter (date, reason, pid, encounter, onset_date, provider_id, facility_id, sensitivity, pc_catid) VALUES (NOW(), 'Upper respiratory symptoms - physical exam pending', $PATIENT_PID, $NEW_ENCOUNTER, '$TODAY', 1, 3, 'normal', 5)" 2>/dev/null
    
    # Also insert into forms table
    openemr_query "INSERT INTO forms (date, encounter, form_name, form_id, pid, user, groupname, authorized, formdir) VALUES (NOW(), $NEW_ENCOUNTER, 'New Patient Encounter', $NEW_ENCOUNTER, $PATIENT_PID, 'admin', 'Default', 1, 'newpatient')" 2>/dev/null
    
    ENCOUNTER_ID=$NEW_ENCOUNTER
    echo "Created new encounter: $ENCOUNTER_ID"
else
    ENCOUNTER_ID=$EXISTING_ENCOUNTER
    echo "Using existing encounter: $ENCOUNTER_ID"
fi

# Save encounter ID for verification
echo "$ENCOUNTER_ID" > /tmp/target_encounter_id.txt

# Record initial form counts for verification
echo "Recording initial form counts..."
INITIAL_FORMS=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_FORMS" > /tmp/initial_form_count.txt
echo "Initial form count for patient: $INITIAL_FORMS"

# Record initial clinical notes count
INITIAL_SOAP=$(openemr_query "SELECT COUNT(*) FROM form_soap WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_SOAP" > /tmp/initial_soap_count.txt
echo "Initial SOAP notes count: $INITIAL_SOAP"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill existing Firefox for clean start
pkill -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

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
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Document Physical Exam Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Encounter ID: $ENCOUNTER_ID"
echo "Date: $TODAY"
echo ""
echo "Task: Document the physical examination findings for this patient's encounter."
echo ""
echo "Required documentation:"
echo "  - General appearance"
echo "  - HEENT examination"
echo "  - Neck examination"
echo "  - Cardiovascular examination"
echo "  - Respiratory examination"
echo "  - Abdominal examination"
echo ""
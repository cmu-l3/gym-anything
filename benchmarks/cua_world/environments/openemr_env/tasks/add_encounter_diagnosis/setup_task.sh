#!/bin/bash
# Setup script for Add Encounter Diagnosis task

echo "=== Setting up Add Encounter Diagnosis Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=2
PATIENT_NAME="Rozella Corkery"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Verify COPD condition exists in problem list
echo "Verifying COPD diagnosis exists for patient..."
COPD_CHECK=$(openemr_query "SELECT id, title, diagnosis FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%obstructive%' OR title LIKE '%COPD%' OR diagnosis LIKE '%185086009%')" 2>/dev/null)
if [ -z "$COPD_CHECK" ]; then
    echo "WARNING: COPD diagnosis not found in problem list"
else
    echo "COPD condition confirmed: $COPD_CHECK"
fi

# Create an encounter for the patient if one doesn't exist today
echo "Checking for existing encounters..."
EXISTING_ENCOUNTER=$(openemr_query "SELECT encounter FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY date DESC LIMIT 1" 2>/dev/null)

if [ -z "$EXISTING_ENCOUNTER" ]; then
    echo "No encounters found. Creating a new encounter for the patient..."
    # Get the max encounter number and add 1
    MAX_ENCOUNTER=$(openemr_query "SELECT COALESCE(MAX(encounter), 0) FROM form_encounter" 2>/dev/null || echo "0")
    NEW_ENCOUNTER=$((MAX_ENCOUNTER + 1))
    
    # Insert new encounter
    openemr_query "INSERT INTO form_encounter (date, reason, facility, pc_catid, facility_id, billing_facility, sensitivity, pid, encounter, onset_date, provider_id) VALUES (NOW(), 'COPD follow-up visit', 'Your Clinic Name Here', 5, 3, 3, 'normal', $PATIENT_PID, $NEW_ENCOUNTER, CURDATE(), 1)" 2>/dev/null
    
    # Also add to forms table
    openemr_query "INSERT INTO forms (date, encounter, form_name, form_id, pid, user, groupname, authorized, formdir) VALUES (NOW(), $NEW_ENCOUNTER, 'New Patient Encounter', 1, $PATIENT_PID, 'admin', 'Default', 1, 'newpatient')" 2>/dev/null
    
    echo "Created encounter: $NEW_ENCOUNTER"
    EXISTING_ENCOUNTER=$NEW_ENCOUNTER
else
    echo "Found existing encounter: $EXISTING_ENCOUNTER"
fi

# Store the target encounter for verification
echo "$EXISTING_ENCOUNTER" > /tmp/target_encounter.txt
echo "Target encounter: $EXISTING_ENCOUNTER"

# Record initial diagnosis count for this patient (ICD10 codes in billing)
INITIAL_DX_COUNT=$(openemr_query "SELECT COUNT(*) FROM billing WHERE pid=$PATIENT_PID AND code_type='ICD10' AND activity=1" 2>/dev/null || echo "0")
echo "$INITIAL_DX_COUNT" > /tmp/initial_dx_count.txt
echo "Initial ICD10 diagnosis count for patient: $INITIAL_DX_COUNT"

# Record initial COPD-specific code count
INITIAL_COPD_COUNT=$(openemr_query "SELECT COUNT(*) FROM billing WHERE pid=$PATIENT_PID AND code_type='ICD10' AND code LIKE 'J44%' AND activity=1" 2>/dev/null || echo "0")
echo "$INITIAL_COPD_COUNT" > /tmp/initial_copd_count.txt
echo "Initial COPD code count: $INITIAL_COPD_COUNT"

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

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo ""
echo "=== Add Encounter Diagnosis Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Condition: COPD (Chronic obstructive bronchitis)"
echo "Target Encounter: $EXISTING_ENCOUNTER"
echo ""
echo "Task: Add ICD-10 diagnosis code J44.1 or J44.9 to the patient's encounter"
echo ""
echo "Login credentials:"
echo "  Username: admin"
echo "  Password: pass"
echo ""
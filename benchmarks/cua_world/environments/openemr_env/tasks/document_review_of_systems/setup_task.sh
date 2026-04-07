#!/bin/bash
# Setup script for Document Review of Systems Task

echo "=== Setting up Document Review of Systems Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=2
PATIENT_NAME="Angelia Kuhic"

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
date -u +"%Y-%m-%d %H:%M:%S" > /tmp/task_start_datetime.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Get initial ROS count for this patient
INITIAL_ROS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_ros WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ROS_COUNT" > /tmp/initial_ros_count.txt
echo "Initial ROS count for patient: $INITIAL_ROS_COUNT"

# Get all initial ROS record IDs to detect new ones
INITIAL_ROS_IDS=$(openemr_query "SELECT GROUP_CONCAT(id) FROM form_ros WHERE pid=$PATIENT_PID" 2>/dev/null || echo "")
echo "$INITIAL_ROS_IDS" > /tmp/initial_ros_ids.txt
echo "Initial ROS IDs: $INITIAL_ROS_IDS"

# Check for existing encounter or create one for today
TODAY=$(date +%Y-%m-%d)
ENCOUNTER_EXISTS=$(openemr_query "SELECT id FROM form_encounter WHERE pid=$PATIENT_PID AND date >= '$TODAY' ORDER BY id DESC LIMIT 1" 2>/dev/null)

if [ -z "$ENCOUNTER_EXISTS" ]; then
    echo "Creating encounter for today..."
    openemr_query "INSERT INTO form_encounter (date, pid, reason, facility_id, provider_id, onset_date, pc_catid) VALUES ('$TODAY 10:00:00', $PATIENT_PID, 'Routine follow-up visit', 3, 1, '$TODAY', 5)" 2>/dev/null
    
    # Get the new encounter ID
    ENCOUNTER_ID=$(openemr_query "SELECT id FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    echo "Created encounter ID: $ENCOUNTER_ID"
    
    # Also create entry in forms table to link encounter
    openemr_query "INSERT INTO forms (date, encounter, form_name, form_id, pid, user, groupname, authorized, formdir) VALUES ('$TODAY 10:00:00', $ENCOUNTER_ID, 'New Patient Encounter', $ENCOUNTER_ID, $PATIENT_PID, 'admin', 'Default', 1, 'newpatient')" 2>/dev/null
else
    ENCOUNTER_ID="$ENCOUNTER_EXISTS"
    echo "Using existing encounter ID: $ENCOUNTER_ID"
fi

echo "$ENCOUNTER_ID" > /tmp/encounter_id.txt
echo "Encounter ID for verification: $ENCOUNTER_ID"

# Ensure Firefox is running and on OpenEMR login page
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
take_screenshot /tmp/task_initial_state.png

echo ""
echo "=== Document Review of Systems Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Encounter ID: $ENCOUNTER_ID"
echo "Initial ROS count: $INITIAL_ROS_COUNT"
echo ""
echo "Task: Document Review of Systems with findings for:"
echo "  - Constitutional: Negative"
echo "  - Cardiovascular: Negative"
echo "  - Respiratory: Negative"
echo "  - Musculoskeletal: POSITIVE (occasional knee stiffness)"
echo ""
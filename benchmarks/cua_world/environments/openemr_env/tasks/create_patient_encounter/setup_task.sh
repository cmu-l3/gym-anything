#!/bin/bash
# Setup script for Create Patient Encounter task

echo "=== Setting up Create Patient Encounter Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    echo "Attempting to verify OpenEMR connection..."
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "SELECT 1" 2>/dev/null && echo "Database connection OK" || echo "Database connection FAILED"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial encounter count for this patient
echo "Recording initial encounter count..."
INITIAL_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ENCOUNTER_COUNT" > /tmp/initial_encounter_count.txt
echo "Initial encounter count for patient pid=$PATIENT_PID: $INITIAL_ENCOUNTER_COUNT"

# Record all existing encounter IDs for this patient (to detect new ones)
openemr_query "SELECT id FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id" 2>/dev/null > /tmp/initial_encounter_ids.txt || true
echo "Existing encounter IDs recorded"

# Get the highest encounter ID overall (to verify new encounter is truly new)
HIGHEST_ENCOUNTER_ID=$(openemr_query "SELECT COALESCE(MAX(id), 0) FROM form_encounter" 2>/dev/null || echo "0")
echo "$HIGHEST_ENCOUNTER_ID" > /tmp/highest_encounter_id.txt
echo "Highest existing encounter ID: $HIGHEST_ENCOUNTER_ID"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|openemr"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Focus and maximize Firefox window
echo "Focusing and maximizing Firefox window..."
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 0.5
fi

# Take initial screenshot for evidence
echo "Taking initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Create Patient Encounter Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1992-06-30)"
echo "Task: Create a new clinical encounter for a same-day visit"
echo "Chief Complaint: Lower back pain"
echo ""
echo "Login credentials:"
echo "  Username: admin"
echo "  Password: pass"
echo ""
echo "Steps:"
echo "  1. Log in to OpenEMR"
echo "  2. Search for patient 'Jayson Fadel'"
echo "  3. Open the patient's chart"
echo "  4. Create new encounter (Encounter menu → New Encounter)"
echo "  5. Set reason to 'Lower back pain' or similar"
echo "  6. Save the encounter"
echo ""
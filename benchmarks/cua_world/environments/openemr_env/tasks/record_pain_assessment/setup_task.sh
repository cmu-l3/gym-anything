#!/bin/bash
# Setup script for Record Pain Assessment Task

echo "=== Setting up Record Pain Assessment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp (critical for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START ($(date -d @$TASK_START))"

# Target patient - Isabella Margarita Gonzalez
# First, find the patient in the database
echo "Searching for patient Isabella Gonzalez..."

# Query for patient with flexible name matching (Synthea may have variations)
PATIENT_DATA=$(openemr_query "SELECT pid, fname, mname, lname, DOB FROM patient_data WHERE fname LIKE 'Isabella%' AND lname LIKE 'Gonzal%' ORDER BY pid LIMIT 1" 2>/dev/null)

if [ -z "$PATIENT_DATA" ]; then
    # Try broader search
    echo "Exact match not found, trying broader search..."
    PATIENT_DATA=$(openemr_query "SELECT pid, fname, mname, lname, DOB FROM patient_data WHERE fname LIKE '%Isabella%' ORDER BY pid LIMIT 1" 2>/dev/null)
fi

if [ -z "$PATIENT_DATA" ]; then
    echo "WARNING: Patient Isabella Gonzalez not found in database"
    echo "Available patients:"
    openemr_query "SELECT pid, fname, lname, DOB FROM patient_data LIMIT 10" 2>/dev/null
    # Use first available patient as fallback
    PATIENT_DATA=$(openemr_query "SELECT pid, fname, mname, lname, DOB FROM patient_data ORDER BY pid LIMIT 1" 2>/dev/null)
fi

# Parse patient info
PATIENT_PID=$(echo "$PATIENT_DATA" | cut -f1)
PATIENT_FNAME=$(echo "$PATIENT_DATA" | cut -f2)
PATIENT_MNAME=$(echo "$PATIENT_DATA" | cut -f3)
PATIENT_LNAME=$(echo "$PATIENT_DATA" | cut -f4)
PATIENT_DOB=$(echo "$PATIENT_DATA" | cut -f5)

echo "Target patient: PID=$PATIENT_PID, Name='$PATIENT_FNAME $PATIENT_MNAME $PATIENT_LNAME', DOB=$PATIENT_DOB"

# Save patient info for verification
cat > /tmp/target_patient.json << EOF
{
    "pid": "$PATIENT_PID",
    "fname": "$PATIENT_FNAME",
    "mname": "$PATIENT_MNAME",
    "lname": "$PATIENT_LNAME",
    "dob": "$PATIENT_DOB"
}
EOF

# Record initial vitals count for this patient
INITIAL_VITALS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_vitals WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_VITALS_COUNT" > /tmp/initial_vitals_count
echo "Initial vitals records for patient: $INITIAL_VITALS_COUNT"

# Record initial encounter count for this patient
INITIAL_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ENCOUNTER_COUNT" > /tmp/initial_encounter_count
echo "Initial encounters for patient: $INITIAL_ENCOUNTER_COUNT"

# Check for any existing pain scores for this patient
EXISTING_PAIN=$(openemr_query "SELECT id, pain, date FROM form_vitals WHERE pid=$PATIENT_PID AND pain IS NOT NULL AND pain != '' ORDER BY date DESC LIMIT 3" 2>/dev/null)
if [ -n "$EXISTING_PAIN" ]; then
    echo "Existing pain records for patient:"
    echo "$EXISTING_PAIN"
fi

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
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Record Pain Assessment Task Setup Complete ==="
echo ""
echo "Task: Document a pain assessment for patient $PATIENT_FNAME $PATIENT_LNAME"
echo ""
echo "Pain Assessment Details to Record:"
echo "  - Pain Score: 7 out of 10"
echo "  - Location: Lower back (lumbar region), radiating to left leg"
echo "  - Quality: Aching, with occasional sharp shooting pain"
echo "  - Duration: Chronic, current episode 2 weeks"
echo ""
echo "Login credentials: admin / pass"
echo ""
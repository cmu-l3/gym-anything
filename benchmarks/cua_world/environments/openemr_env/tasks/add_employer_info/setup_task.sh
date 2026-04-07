#!/bin/bash
# Setup script for Add Employer Information Task

echo "=== Setting up Add Employer Information Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient details
TARGET_FNAME="Maria"
TARGET_LNAME="Klein"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Record initial employer_data count for comparison
echo "Recording initial employer data count..."
INITIAL_EMPLOYER_COUNT=$(openemr_query "SELECT COUNT(*) FROM employer_data" 2>/dev/null || echo "0")
echo "$INITIAL_EMPLOYER_COUNT" > /tmp/initial_employer_count
echo "Initial employer_data count: $INITIAL_EMPLOYER_COUNT"

# Find the target patient
echo "Looking for patient $TARGET_FNAME $TARGET_LNAME..."
PATIENT_DATA=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE fname='$TARGET_FNAME' AND lname='$TARGET_LNAME' LIMIT 1" 2>/dev/null)

if [ -z "$PATIENT_DATA" ]; then
    # Try case-insensitive search
    PATIENT_DATA=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE LOWER(fname)=LOWER('$TARGET_FNAME') AND LOWER(lname)=LOWER('$TARGET_LNAME') LIMIT 1" 2>/dev/null)
fi

if [ -z "$PATIENT_DATA" ]; then
    echo "WARNING: Patient $TARGET_FNAME $TARGET_LNAME not found!"
    echo "Available patients:"
    openemr_query "SELECT pid, fname, lname FROM patient_data LIMIT 10" 2>/dev/null
    
    # Use first available patient as fallback
    PATIENT_DATA=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data LIMIT 1" 2>/dev/null)
    if [ -n "$PATIENT_DATA" ]; then
        TARGET_PID=$(echo "$PATIENT_DATA" | cut -f1)
        TARGET_FNAME=$(echo "$PATIENT_DATA" | cut -f2)
        TARGET_LNAME=$(echo "$PATIENT_DATA" | cut -f3)
        echo "Using fallback patient: $TARGET_FNAME $TARGET_LNAME (pid=$TARGET_PID)"
    fi
else
    TARGET_PID=$(echo "$PATIENT_DATA" | cut -f1)
    echo "Patient found: $TARGET_FNAME $TARGET_LNAME (pid=$TARGET_PID)"
fi

# Save target patient info for verification
echo "$TARGET_PID" > /tmp/target_patient_pid
echo "$TARGET_FNAME" > /tmp/target_patient_fname
echo "$TARGET_LNAME" > /tmp/target_patient_lname

# Clear any existing employer association for this patient (clean state)
if [ -n "$TARGET_PID" ]; then
    echo "Clearing any existing employer for patient pid=$TARGET_PID..."
    # Get current employer ID if exists
    CURRENT_EMPLOYER=$(openemr_query "SELECT employer FROM patient_data WHERE pid=$TARGET_PID" 2>/dev/null)
    echo "Current employer ID: $CURRENT_EMPLOYER"
    echo "$CURRENT_EMPLOYER" > /tmp/initial_employer_id
    
    # Don't delete employer records, just clear the association
    # This ensures clean state for verification
    openemr_query "UPDATE patient_data SET employer=NULL WHERE pid=$TARGET_PID" 2>/dev/null || true
fi

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
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Add Employer Information Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR"
echo "     - Username: admin"
echo "     - Password: pass"
echo ""
echo "  2. Search for patient: $TARGET_FNAME $TARGET_LNAME"
echo ""
echo "  3. Navigate to Demographics and find Employer section"
echo ""
echo "  4. Add the following employer information:"
echo "     - Employer Name: Precision Manufacturing LLC"
echo "     - Street Address: 2750 Commerce Boulevard"
echo "     - City: Worcester"
echo "     - State: MA"
echo "     - Postal Code: 01608"
echo "     - Country: USA"
echo ""
echo "  5. Save the patient record"
echo ""
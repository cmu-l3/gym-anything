#!/bin/bash
# Setup script for Add Patient Guarantor task

echo "=== Setting up Add Patient Guarantor Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient info
PATIENT_FNAME="Pedro"
PATIENT_LNAME="Gusikowski"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Ensure OpenEMR containers are running
cd /home/ga/openemr
if ! docker-compose ps 2>/dev/null | grep -q "Up"; then
    echo "Starting OpenEMR containers..."
    docker-compose up -d
    sleep 10
fi

# Wait for OpenEMR to be ready
echo "Waiting for OpenEMR to be ready..."
for i in {1..30}; do
    if curl -s http://localhost/interface/login/login.php > /dev/null 2>&1; then
        echo "OpenEMR is ready"
        break
    fi
    sleep 2
done

# Find patient Pedro Gusikowski and get their PID
echo "Looking for patient $PATIENT_FNAME $PATIENT_LNAME..."
PATIENT_PID=$(openemr_query "SELECT pid FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME' LIMIT 1" 2>/dev/null)

if [ -z "$PATIENT_PID" ]; then
    echo "ERROR: Patient $PATIENT_FNAME $PATIENT_LNAME not found in database!"
    echo "Available patients:"
    openemr_query "SELECT pid, fname, lname FROM patient_data LIMIT 10" 2>/dev/null
    exit 1
fi

echo "Found patient $PATIENT_FNAME $PATIENT_LNAME with PID=$PATIENT_PID"
echo "$PATIENT_PID" > /tmp/task_patient_pid.txt

# Record current guarantor state (for verification that it was empty/changed)
echo "Recording initial guarantor state..."
INITIAL_GUARDIAN=$(openemr_query "SELECT guardiansname, guardianstreet, guardiancity, guardianstate, guardianpostalcode, guardianphone FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "$INITIAL_GUARDIAN" > /tmp/initial_guardian_state.txt
echo "Initial guarantor data: $INITIAL_GUARDIAN"

# Clear any existing guarantor information to ensure clean initial state
echo "Clearing existing guarantor information for clean test..."
openemr_query "UPDATE patient_data SET guardiansname='', guardianstreet='', guardiancity='', guardianstate='', guardianpostalcode='', guardianphone='' WHERE pid=$PATIENT_PID" 2>/dev/null

# Verify fields are cleared
CLEARED_CHECK=$(openemr_query "SELECT guardiansname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Guarantor name after clearing (should be empty): '$CLEARED_CHECK'"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill any existing Firefox instances for clean start
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
echo "Starting Firefox with OpenEMR..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing and maximizing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for audit
sleep 2
take_screenshot /tmp/task_initial_state.png

echo ""
echo "=== Add Patient Guarantor Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_FNAME $PATIENT_LNAME (PID: $PATIENT_PID)"
echo "Patient DOB: 2011-04-05 (minor - requires guarantor)"
echo ""
echo "Task: Add the following guarantor information:"
echo "  - Name: Maria Gusikowski"
echo "  - Relationship: Parent"
echo "  - Address: 661 Nikolaus Well, Northampton, MA 01060"
echo "  - Phone: (413) 555-0198"
echo ""
echo "OpenEMR Login: admin / pass"
echo ""
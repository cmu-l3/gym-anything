#!/bin/bash
# Setup script for Generate Patient CCD Task

echo "=== Setting up Generate Patient CCD Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient details
PATIENT_PID=5
PATIENT_FNAME="Rickie"
PATIENT_LNAME="Batz"
PATIENT_DOB="1990-08-14"

# Record task start timestamp (critical for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START ($(date -d @$TASK_START))"

# Clear any existing XML files from download locations to ensure clean state
echo "Clearing old XML files from download locations..."
rm -f /home/ga/Downloads/*.xml 2>/dev/null || true
rm -f /home/ga/Downloads/*.ccd 2>/dev/null || true
rm -f /home/ga/*.xml 2>/dev/null || true
rm -f /tmp/*.xml 2>/dev/null || true
rm -f /tmp/ccd_*.* 2>/dev/null || true

# Ensure Downloads directory exists and is writable
echo "Ensuring Downloads directory exists..."
mkdir -p /home/ga/Downloads
chown ga:ga /home/ga/Downloads
chmod 755 /home/ga/Downloads

# Record initial state - list of existing files in potential download locations
echo "Recording initial file state..."
find /home/ga/Downloads /home/ga /tmp -maxdepth 2 -name "*.xml" -type f 2>/dev/null | sort > /tmp/initial_xml_files.txt
echo "Initial XML files:"
cat /tmp/initial_xml_files.txt

# Verify patient exists in database
echo ""
echo "Verifying patient $PATIENT_FNAME $PATIENT_LNAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    echo "Checking all patients..."
    openemr_query "SELECT pid, fname, lname FROM patient_data LIMIT 10" 2>/dev/null
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Verify patient has clinical data (conditions)
echo ""
echo "Verifying patient has clinical conditions..."
CONDITIONS=$(openemr_query "SELECT id, title FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' LIMIT 5" 2>/dev/null)
if [ -n "$CONDITIONS" ]; then
    echo "Conditions found:"
    echo "$CONDITIONS"
else
    echo "WARNING: No conditions found for patient (CCD may be sparse)"
fi

# Verify patient has medications
echo ""
echo "Verifying patient has medications..."
MEDICATIONS=$(openemr_query "SELECT id, drug FROM prescriptions WHERE patient_id=$PATIENT_PID LIMIT 5" 2>/dev/null)
if [ -n "$MEDICATIONS" ]; then
    echo "Medications found:"
    echo "$MEDICATIONS"
else
    echo "WARNING: No medications found for patient"
fi

# Verify patient has allergies
echo ""
echo "Checking for allergies..."
ALLERGIES=$(openemr_query "SELECT id, title FROM lists WHERE pid=$PATIENT_PID AND type='allergy' LIMIT 5" 2>/dev/null)
if [ -n "$ALLERGIES" ]; then
    echo "Allergies found:"
    echo "$ALLERGIES"
else
    echo "Note: No allergies recorded for patient"
fi

# Ensure Firefox is running on OpenEMR login page
echo ""
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
sleep 2
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved to /tmp/task_initial_screenshot.png"

echo ""
echo "=== Generate Patient CCD Task Setup Complete ==="
echo ""
echo "TASK: Generate a CCD (Continuity of Care Document) for patient transfer"
echo ""
echo "Patient Details:"
echo "  Name: $PATIENT_FNAME $PATIENT_LNAME"
echo "  DOB: $PATIENT_DOB"
echo "  Patient ID: $PATIENT_PID"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (admin/pass)"
echo "  2. Find and select patient $PATIENT_FNAME $PATIENT_LNAME"
echo "  3. Navigate to CCD export (Reports menu or patient chart)"
echo "  4. Generate and download the CCD document"
echo ""
echo "The CCD file will be saved to /home/ga/Downloads/ or displayed in browser"
echo ""
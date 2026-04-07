#!/bin/bash
# Setup script for Update Emergency Contact Task

echo "=== Setting up Update Emergency Contact Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=2
PATIENT_NAME="Frances Will"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial emergency contact values for anti-gaming verification
echo "Recording initial emergency contact values..."
INITIAL_EM_DATA=$(openemr_query "SELECT em_contact, em_phone FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
INITIAL_EM_CONTACT=$(echo "$INITIAL_EM_DATA" | cut -f1)
INITIAL_EM_PHONE=$(echo "$INITIAL_EM_DATA" | cut -f2)

echo "Initial emergency contact: '$INITIAL_EM_CONTACT'"
echo "Initial emergency phone: '$INITIAL_EM_PHONE'"

# Save initial values for later comparison
echo "$INITIAL_EM_CONTACT" > /tmp/initial_em_contact.txt
echo "$INITIAL_EM_PHONE" > /tmp/initial_em_phone.txt

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Get the last modified date for the patient record (if available)
INITIAL_MODIFIED=$(openemr_query "SELECT UNIX_TIMESTAMP(date) FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_MODIFIED" > /tmp/initial_patient_modified.txt
echo "Initial patient record timestamp: $INITIAL_MODIFIED"

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
echo "=== Update Emergency Contact Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR (Username: admin, Password: pass)"
echo ""
echo "  2. Search for patient: Frances Will"
echo ""
echo "  3. Open the patient's Demographics section"
echo ""
echo "  4. Update emergency contact information:"
echo "     - Contact Name: Robert Will"
echo "     - Relationship: Spouse"
echo "     - Phone: (617) 555-9876"
echo ""
echo "  5. Save the changes"
echo ""
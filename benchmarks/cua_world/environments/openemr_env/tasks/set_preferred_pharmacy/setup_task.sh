#!/bin/bash
# Setup script for Set Preferred Pharmacy Task

echo "=== Setting up Set Preferred Pharmacy Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient and pharmacy
PATIENT_PID=5
PATIENT_NAME="Antonia Gottlieb"
TARGET_PHARMACY_ID=50
TARGET_PHARMACY_NAME="CVS Pharmacy - Downtown"

# Record task start timestamp for anti-gaming
echo "Recording task start time..."
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Record initial pharmacy assignment for this patient
echo "Recording initial pharmacy assignment..."
INITIAL_PHARMACY=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COALESCE(pharmacy_id, 'NULL') FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "NULL")
echo "$INITIAL_PHARMACY" > /tmp/initial_pharmacy.txt
echo "Initial pharmacy_id for patient $PATIENT_PID: $INITIAL_PHARMACY"

# Ensure the target pharmacy exists in the system
echo "Ensuring target pharmacy exists in system..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
INSERT INTO pharmacies (id, name, transmit_method, email, ncpdp, npi, address, city, state, zip, phone, fax)
VALUES ($TARGET_PHARMACY_ID, '$TARGET_PHARMACY_NAME', 1, 'cvs.downtown@example.com', '1234567', '1234567890',
        '100 Main Street', 'Springfield', 'MA', '01103', '(413) 555-0199', '(413) 555-0198')
ON DUPLICATE KEY UPDATE 
    name = '$TARGET_PHARMACY_NAME',
    address = '100 Main Street',
    city = 'Springfield',
    state = 'MA',
    zip = '01103',
    phone = '(413) 555-0199',
    fax = '(413) 555-0198',
    ncpdp = '1234567';
" 2>/dev/null || true

# Verify pharmacy was created
PHARMACY_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, name FROM pharmacies WHERE id=$TARGET_PHARMACY_ID" 2>/dev/null)
echo "Target pharmacy verified: $PHARMACY_CHECK"

# Clear any existing pharmacy assignment for clean test state
echo "Clearing existing pharmacy assignment for clean test..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "UPDATE patient_data SET pharmacy_id = NULL WHERE pid = $PATIENT_PID" 2>/dev/null || true

# Verify patient exists
echo "Verifying patient exists..."
PATIENT_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# List available pharmacies for debugging
echo ""
echo "Available pharmacies in system:"
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT id, name, city, state FROM pharmacies ORDER BY name LIMIT 10" 2>/dev/null || true

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

# Dismiss any popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo ""
echo "=== Set Preferred Pharmacy Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Target Pharmacy: $TARGET_PHARMACY_NAME (ID: $TARGET_PHARMACY_ID)"
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR (admin / pass)"
echo "  2. Search for patient '$PATIENT_NAME'"
echo "  3. Open patient's Demographics"
echo "  4. Set Pharmacy to '$TARGET_PHARMACY_NAME'"
echo "  5. Save the changes"
echo ""
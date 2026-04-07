#!/bin/bash
# Setup script for Assign Primary Care Provider Task

echo "=== Setting up Assign Primary Care Provider Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient and provider
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"
PROVIDER_USERNAME="physician"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp.txt
echo "Task start timestamp: $(cat /tmp/task_start_timestamp.txt)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Verify provider exists
echo "Verifying provider $PROVIDER_USERNAME exists..."
PROVIDER_CHECK=$(openemr_query "SELECT id, username, fname, lname, authorized, active FROM users WHERE username='$PROVIDER_USERNAME'" 2>/dev/null)
if [ -z "$PROVIDER_CHECK" ]; then
    echo "ERROR: Provider not found in database!"
    exit 1
fi
echo "Provider found: $PROVIDER_CHECK"

# Extract provider ID for verification later
PROVIDER_ID=$(openemr_query "SELECT id FROM users WHERE username='$PROVIDER_USERNAME'" 2>/dev/null)
echo "$PROVIDER_ID" > /tmp/expected_provider_id.txt
echo "Expected provider ID: $PROVIDER_ID"

# Record initial provider assignment (for anti-gaming - detect if already set)
INITIAL_PROVIDER_ID=$(openemr_query "SELECT COALESCE(providerID, 0) FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_PROVIDER_ID" > /tmp/initial_provider_id.txt
echo "Initial providerID for patient: $INITIAL_PROVIDER_ID"

# Clear any existing provider assignment to ensure clean state
echo "Clearing any existing provider assignment..."
openemr_query "UPDATE patient_data SET providerID = NULL WHERE pid=$PATIENT_PID" 2>/dev/null || true

# Verify provider was cleared
CLEARED_PROVIDER=$(openemr_query "SELECT COALESCE(providerID, 0) FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Provider after clearing: $CLEARED_PROVIDER"

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

# Take initial screenshot for verification
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Assign Primary Care Provider Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR"
echo "     - Username: admin"
echo "     - Password: pass"
echo ""
echo "  2. Search for patient: Jayson Fadel (DOB: 1992-06-30)"
echo ""
echo "  3. Open the patient's chart"
echo ""
echo "  4. Navigate to demographics/provider section"
echo ""
echo "  5. Set Primary Care Provider to: Philip Katz"
echo ""
echo "  6. Save the changes"
echo ""
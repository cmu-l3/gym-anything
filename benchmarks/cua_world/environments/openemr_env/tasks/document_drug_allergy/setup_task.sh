#!/bin/bash
# Setup script for Document Drug Allergy task
# Records initial state and prepares environment

echo "=== Setting up Document Drug Allergy Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=5
PATIENT_NAME="Maria Maggio"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    echo "Available patients:"
    openemr_query "SELECT pid, fname, lname FROM patient_data LIMIT 10" 2>/dev/null
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial allergy count for this patient (anti-gaming)
echo "Recording initial allergy count..."
INITIAL_ALLERGY_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='allergy'" 2>/dev/null || echo "0")
echo "$INITIAL_ALLERGY_COUNT" > /tmp/initial_allergy_count.txt
echo "Initial allergy count for Maria Maggio: $INITIAL_ALLERGY_COUNT"

# Check if Penicillin allergy already exists (for baseline comparison)
echo "Checking for pre-existing Penicillin allergy..."
EXISTING_PCN=$(openemr_query "SELECT id, title FROM lists WHERE pid=$PATIENT_PID AND type='allergy' AND LOWER(title) LIKE '%penicillin%'" 2>/dev/null)
if [ -n "$EXISTING_PCN" ]; then
    echo "WARNING: Penicillin allergy already exists: $EXISTING_PCN"
    echo "$EXISTING_PCN" > /tmp/existing_pcn_allergy.txt
else
    echo "No pre-existing Penicillin allergy found (good - clean state)"
    echo "" > /tmp/existing_pcn_allergy.txt
fi

# List current allergies for this patient (debug info)
echo ""
echo "Current allergies for patient $PATIENT_PID:"
openemr_query "SELECT id, title, reaction, severity_al FROM lists WHERE pid=$PATIENT_PID AND type='allergy'" 2>/dev/null || echo "(none)"
echo ""

# Ensure Firefox is running with OpenEMR login page
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

# Navigate to login page (ensure clean state)
echo "Navigating to OpenEMR login page..."
su - ga -c "DISPLAY=:1 xdotool key ctrl+l" 2>/dev/null || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type '$OPENEMR_URL'" 2>/dev/null || true
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 3

# Take initial screenshot for audit
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Document Drug Allergy Task Setup Complete ==="
echo ""
echo "Task: Document a new drug allergy for patient Maria Maggio"
echo ""
echo "Patient Details:"
echo "  - Name: Maria Maggio"
echo "  - DOB: 1973-05-01"
echo "  - Patient ID: 5"
echo ""
echo "Allergy to Document:"
echo "  - Allergen: Penicillin"
echo "  - Reaction: Hives"
echo "  - Severity: Moderate"
echo ""
echo "Login: admin / pass"
echo ""
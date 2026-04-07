#!/bin/bash
# Setup script for Set Communication Preference Task

echo "=== Setting up Set Communication Preference Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=5
PATIENT_NAME="Sofia Bradtke"

# Record task start timestamp (for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial HIPAA preferences for verification (before task)
echo "Recording initial HIPAA communication preferences..."
INITIAL_PREFS=$(openemr_query "SELECT hipaa_allowemail, hipaa_voice, hipaa_allowsms, hipaa_mail FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Initial preferences: $INITIAL_PREFS"

# Parse and save individual values
INITIAL_ALLOWEMAIL=$(echo "$INITIAL_PREFS" | cut -f1)
INITIAL_VOICE=$(echo "$INITIAL_PREFS" | cut -f2)
INITIAL_ALLOWSMS=$(echo "$INITIAL_PREFS" | cut -f3)
INITIAL_MAIL=$(echo "$INITIAL_PREFS" | cut -f4)

# Save initial state to file
cat > /tmp/initial_hipaa_prefs.json << EOF
{
    "patient_pid": $PATIENT_PID,
    "hipaa_allowemail": "$INITIAL_ALLOWEMAIL",
    "hipaa_voice": "$INITIAL_VOICE",
    "hipaa_allowsms": "$INITIAL_ALLOWSMS",
    "hipaa_mail": "$INITIAL_MAIL",
    "timestamp": "$(date -Iseconds)"
}
EOF
echo "Initial HIPAA preferences saved to /tmp/initial_hipaa_prefs.json"
cat /tmp/initial_hipaa_prefs.json

# Record last modification timestamp for the patient record
INITIAL_DATE=$(openemr_query "SELECT date FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "$INITIAL_DATE" > /tmp/initial_patient_date
echo "Initial patient record date: $INITIAL_DATE"

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

# Take initial screenshot for audit
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Set Communication Preference Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR"
echo "     - Username: admin"
echo "     - Password: pass"
echo ""
echo "  2. Search for patient: Sofia Bradtke"
echo ""
echo "  3. Open patient Demographics and click Edit"
echo ""
echo "  4. Find HIPAA/Communication preferences section and update:"
echo "     - Allow Email: YES"
echo "     - Allow Voice Message: NO"
echo ""
echo "  5. Save the changes"
echo ""
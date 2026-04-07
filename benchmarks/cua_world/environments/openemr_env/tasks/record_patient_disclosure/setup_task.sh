#!/bin/bash
# Setup script for Record Patient Disclosure Task

echo "=== Setting up Record Patient Disclosure Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=5
PATIENT_NAME="Verla Denesik"

# Record task start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial disclosure count for this patient
# Check extended_log table for disclosure events
echo "Recording initial disclosure count..."
INITIAL_DISCLOSURE_COUNT=$(openemr_query "SELECT COUNT(*) FROM extended_log WHERE patient_id=$PATIENT_PID AND event LIKE '%disclosure%'" 2>/dev/null || echo "0")

# Also check if there's a dedicated disclosure table
DISCLOSURE_TABLE_EXISTS=$(openemr_query "SHOW TABLES LIKE 'disclosure'" 2>/dev/null || echo "")
if [ -n "$DISCLOSURE_TABLE_EXISTS" ]; then
    INITIAL_DISCLOSURE_TABLE_COUNT=$(openemr_query "SELECT COUNT(*) FROM disclosure WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
    echo "Disclosure table exists. Initial count: $INITIAL_DISCLOSURE_TABLE_COUNT"
else
    INITIAL_DISCLOSURE_TABLE_COUNT="0"
    echo "No dedicated disclosure table found. Using extended_log."
fi

echo "$INITIAL_DISCLOSURE_COUNT" > /tmp/initial_disclosure_count.txt
echo "$INITIAL_DISCLOSURE_TABLE_COUNT" > /tmp/initial_disclosure_table_count.txt
echo "Initial disclosure count (extended_log): $INITIAL_DISCLOSURE_COUNT"

# Record all current disclosure-related entries for comparison
echo "Recording existing disclosures for patient..."
openemr_query "SELECT id, date, event, recipient, comments FROM extended_log WHERE patient_id=$PATIENT_PID AND event LIKE '%disclosure%' ORDER BY id DESC LIMIT 10" 2>/dev/null > /tmp/initial_disclosures.txt || true

# Ensure Firefox is running and focused on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill any existing Firefox to start fresh
pkill -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

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
echo "=== Record Patient Disclosure Task Setup Complete ==="
echo ""
echo "TASK: Record a HIPAA disclosure for patient $PATIENT_NAME"
echo ""
echo "Patient Details:"
echo "  - Name: Verla Denesik"
echo "  - DOB: 1966-10-23"
echo "  - PID: 5"
echo ""
echo "Disclosure Details to Record:"
echo "  - Recipient: Law Offices of Johnson & Associates"
echo "  - Address: 450 Legal Plaza, Suite 200, Springfield, MA 01103"
echo "  - Type: Legal/patient-authorized disclosure"
echo "  - Description: Complete medical records released per patient"
echo "                 authorization for personal injury claim."
echo ""
echo "Login credentials: admin / pass"
echo ""
#!/bin/bash
# Setup script for Send Portal Message Task

echo "=== Setting up Send Portal Message Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Check patient portal access status
echo "Checking patient portal access..."
PORTAL_STATUS=$(openemr_query "SELECT portal_username, allow_patient_portal FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Portal status: $PORTAL_STATUS"

# Record initial message counts for verification
# Check pnotes table (general patient notes/messages)
INITIAL_PNOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_PNOTES_COUNT" > /tmp/initial_pnotes_count
echo "Initial pnotes count for patient: $INITIAL_PNOTES_COUNT"

# Check onsite_messages table (patient portal messages) if it exists
INITIAL_PORTAL_MSG_COUNT=$(openemr_query "SELECT COUNT(*) FROM onsite_messages WHERE recip_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_PORTAL_MSG_COUNT" > /tmp/initial_portal_msg_count
echo "Initial portal messages count: $INITIAL_PORTAL_MSG_COUNT"

# Check onsite_mail table (another possible messaging table)
INITIAL_ONSITE_MAIL_COUNT=$(openemr_query "SELECT COUNT(*) FROM onsite_mail WHERE recipient_id='$PATIENT_PID'" 2>/dev/null || echo "0")
echo "$INITIAL_ONSITE_MAIL_COUNT" > /tmp/initial_onsite_mail_count
echo "Initial onsite mail count: $INITIAL_ONSITE_MAIL_COUNT"

# Get list of all message-related tables for debugging
echo ""
echo "=== Available messaging tables ==="
openemr_query "SHOW TABLES LIKE '%message%'" 2>/dev/null || true
openemr_query "SHOW TABLES LIKE '%note%'" 2>/dev/null || true
openemr_query "SHOW TABLES LIKE '%mail%'" 2>/dev/null || true
openemr_query "SHOW TABLES LIKE '%portal%'" 2>/dev/null || true
echo "=== End table list ==="
echo ""

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
echo "=== Send Portal Message Task Setup Complete ==="
echo ""
echo "TASK: Send a secure message to patient Jayson Fadel"
echo ""
echo "Patient Details:"
echo "  Name: $PATIENT_NAME"
echo "  PID: $PATIENT_PID"
echo "  DOB: 1992-06-30"
echo ""
echo "Message Requirements:"
echo "  Subject: 'Lab Results - Please Schedule Follow-up'"
echo "  Body must include:"
echo "    - Reference to lab results being available"
echo "    - Request to schedule a follow-up appointment"
echo "    - Phone number for scheduling: 555-0100"
echo "    - Professional closing"
echo ""
echo "Login credentials: admin / pass"
echo ""
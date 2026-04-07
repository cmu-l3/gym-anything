#!/bin/bash
# Setup script for Send Internal Message task

echo "=== Setting up Send Internal Message Task ==="

# Source shared utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Configuration
PATIENT_PID=4
PATIENT_NAME="Rosa Fritsch"

# Record task start time for anti-gaming verification
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt
echo "Task start time recorded: $TASK_START ($(date -d @$TASK_START))"

# Record initial message count for this patient
echo "Recording initial message count for patient PID=$PATIENT_PID..."
INITIAL_MSG_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_MSG_COUNT" > /tmp/initial_message_count.txt
echo "Initial message count for patient: $INITIAL_MSG_COUNT"

# Also record total message count (for detecting any new messages)
TOTAL_MSG_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM pnotes" 2>/dev/null || echo "0")
echo "$TOTAL_MSG_COUNT" > /tmp/initial_total_message_count.txt
echo "Initial total message count: $TOTAL_MSG_COUNT"

# Verify patient exists in database
echo ""
echo "Verifying patient $PATIENT_NAME exists..."
PATIENT_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)

if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient Rosa Fritsch (PID=$PATIENT_PID) not found in database"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Check for available provider users to receive the message
echo ""
echo "Checking available provider users..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT id, username, fname, lname, authorized FROM users WHERE active=1 AND authorized=1 LIMIT 5" 2>/dev/null || true

# Check if Philip Ho exists specifically
PHILIP_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, username FROM users WHERE (fname LIKE '%Philip%' OR lname LIKE '%Ho%') AND active=1" 2>/dev/null || echo "")
if [ -n "$PHILIP_CHECK" ]; then
    echo "Found Philip Ho user: $PHILIP_CHECK"
else
    echo "Note: Philip Ho user may not exist - agent should find an appropriate provider"
fi

# Ensure Firefox is running with OpenEMR
echo ""
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox with OpenEMR..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window to appear
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|openemr"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox window maximized and focused (WID: $WID)"
    sleep 1
fi

# Allow page to fully load
sleep 3

# Take initial screenshot for verification
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot saved: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Send Internal Provider Message"
echo "====================================="
echo ""
echo "Clinical Scenario:"
echo "  Patient Rosa Fritsch (DOB: 1952-04-04) has elevated BP: 158/94 mmHg"
echo "  Send a message to alert the physician before the visit."
echo ""
echo "Login: admin / pass"
echo ""
echo "Required Message Details:"
echo "  - Recipient: Dr. Philip Ho (or any available provider)"
echo "  - Patient: Rosa Fritsch (PID 4)"
echo "  - Subject: 'Elevated BP Alert - Rosa Fritsch'"
echo "  - Body: Include BP reading 158/94 and request review"
echo ""
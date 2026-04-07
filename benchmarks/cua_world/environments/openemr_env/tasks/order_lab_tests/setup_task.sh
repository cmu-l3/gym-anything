#!/bin/bash
echo "=== Setting up order_lab_tests task ==="

# Source common utilities
source /workspace/scripts/task_utils.sh

# Target patient information
PATIENT_PID=5
PATIENT_NAME="Rosetta Effertz"

# Record task start time (CRITICAL for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Record initial procedure order count for this patient
echo "Recording initial procedure order state..."
INITIAL_ORDER_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_order WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ORDER_COUNT" > /tmp/initial_order_count.txt
echo "Initial procedure orders for patient $PATIENT_PID: $INITIAL_ORDER_COUNT"

# Also record total order count to detect any new orders
TOTAL_ORDER_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_order" 2>/dev/null || echo "0")
echo "$TOTAL_ORDER_COUNT" > /tmp/initial_total_order_count.txt
echo "Total procedure orders in system: $TOTAL_ORDER_COUNT"

# Get the highest procedure_order_id to identify new orders later
MAX_ORDER_ID=$(openemr_query "SELECT COALESCE(MAX(procedure_order_id), 0) FROM procedure_order" 2>/dev/null || echo "0")
echo "$MAX_ORDER_ID" > /tmp/initial_max_order_id.txt
echo "Current max procedure_order_id: $MAX_ORDER_ID"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database! Task cannot proceed."
    exit 1
fi
echo "Patient verified: $PATIENT_CHECK"

# Save patient info for verification
echo "$PATIENT_CHECK" > /tmp/patient_info.txt

# Ensure Firefox is running and showing OpenEMR login page
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

echo "Checking Firefox status..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox with OpenEMR..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
else
    echo "Firefox already running"
fi

# Wait for Firefox window to appear
echo "Waiting for Firefox window..."
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected within timeout"
fi

# Get Firefox window ID and maximize
sleep 2
FIREFOX_WID=$(get_firefox_window_id)
if [ -n "$FIREFOX_WID" ]; then
    echo "Firefox window ID: $FIREFOX_WID"
    DISPLAY=:1 wmctrl -ia "$FIREFOX_WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox window maximized and focused"
else
    echo "WARNING: Could not find Firefox window ID"
fi

# Navigate to login page (ensure clean state)
echo "Navigating to OpenEMR login page..."
su - ga -c "DISPLAY=:1 xdotool key ctrl+l" 2>/dev/null || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type '$OPENEMR_URL'" 2>/dev/null || true
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 3

# Take initial screenshot for verification evidence
echo "Taking initial screenshot..."
take_screenshot /tmp/task_initial_state.png
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "Target Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1965-04-18)"
echo "Task: Order a Lipid Panel laboratory test for annual wellness exam"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (admin / pass)"
echo "  2. Search for patient 'Rosetta Effertz'"
echo "  3. Navigate to Procedures > Procedure Order"
echo "  4. Create order for Lipid Panel"
echo "  5. Add clinical note: 'Annual wellness exam - cardiovascular screening'"
echo "  6. Save the order"
echo ""
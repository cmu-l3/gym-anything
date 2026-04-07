#!/bin/bash
# Setup script for Order Radiology Procedure Task
echo "=== Setting up Order Radiology Procedure Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient information
PATIENT_PID=4
PATIENT_NAME="Ruben Bayer"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    echo "Attempting to check all patients..."
    openemr_query "SELECT pid, fname, lname FROM patient_data LIMIT 10" 2>/dev/null
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial procedure order count for this patient
echo "Recording initial procedure order count..."
INITIAL_PROC_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_order WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_PROC_COUNT" > /tmp/initial_procedure_count.txt
echo "Initial procedure order count for patient: $INITIAL_PROC_COUNT"

# Also record initial billing count as alternative check
INITIAL_BILLING_COUNT=$(openemr_query "SELECT COUNT(*) FROM billing WHERE pid=$PATIENT_PID AND code_type IN ('CPT4', 'HCPCS', 'CPT')" 2>/dev/null || echo "0")
echo "$INITIAL_BILLING_COUNT" > /tmp/initial_billing_count.txt
echo "Initial billing count for patient: $INITIAL_BILLING_COUNT"

# Record initial forms count (for fee sheet entries)
INITIAL_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_FORMS_COUNT" > /tmp/initial_forms_count.txt
echo "Initial forms count for patient: $INITIAL_FORMS_COUNT"

# Ensure Firefox is running with OpenEMR
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
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
    sleep 0.5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox window focused and maximized: $WID"
else
    echo "WARNING: Could not find Firefox window ID"
fi

# Dismiss any startup dialogs
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for evidence
echo "Capturing initial screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Order Radiology Procedure Task Setup Complete ==="
echo ""
echo "Patient Information:"
echo "  Name: $PATIENT_NAME"
echo "  PID: $PATIENT_PID"
echo "  DOB: 1955-08-22 (67 years old)"
echo ""
echo "Clinical Scenario:"
echo "  Patient presents with 5-day history of:"
echo "    - Productive cough"
echo "    - Fever (101.2°F)"
echo "    - Shortness of breath (dyspnea)"
echo ""
echo "Task: Order a Chest X-Ray (PA and Lateral views)"
echo "      Clinical indication: Evaluate for pneumonia"
echo "      Priority: Normal"
echo ""
echo "Login credentials: admin / pass"
echo ""
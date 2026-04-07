#!/bin/bash
# Setup script for Document Medical Device Task

echo "=== Setting up Document Medical Device Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start time (for anti-gaming timestamp verification)
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

# Record initial count of device-related entries for this patient
# This helps detect if a new entry was added vs. pre-existing
echo "Recording initial device entry count..."
INITIAL_DEVICE_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND (LOWER(title) LIKE '%pacemaker%' OR LOWER(title) LIKE '%implant%' OR LOWER(title) LIKE '%device%' OR LOWER(comments) LIKE '%medtronic%' OR LOWER(comments) LIKE '%pjn847291%')" 2>/dev/null || echo "0")
echo "$INITIAL_DEVICE_COUNT" > /tmp/initial_device_count.txt
echo "Initial device entries for patient: $INITIAL_DEVICE_COUNT"

# Also record total lists count for this patient
INITIAL_LISTS_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_LISTS_COUNT" > /tmp/initial_lists_count.txt
echo "Initial total list entries for patient: $INITIAL_LISTS_COUNT"

# Record highest list ID to detect new entries
MAX_LIST_ID=$(openemr_query "SELECT COALESCE(MAX(id), 0) FROM lists" 2>/dev/null || echo "0")
echo "$MAX_LIST_ID" > /tmp/initial_max_list_id.txt
echo "Initial max list ID: $MAX_LIST_ID"

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
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Document Medical Device Task Setup Complete ==="
echo ""
echo "Task: Document an implanted cardiac pacemaker for patient $PATIENT_NAME"
echo ""
echo "Device Details to Document:"
echo "  - Type: Cardiac Pacemaker"
echo "  - Manufacturer: Medtronic"
echo "  - Model: Azure XT DR MRI SureScan"
echo "  - Serial Number: PJN847291"
echo "  - Implant Date: 2024-09-15"
echo "  - Location: Left chest (subclavicular)"
echo "  - MRI Status: Conditional"
echo ""
echo "Login credentials: admin / pass"
echo ""
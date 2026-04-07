#!/bin/bash
# Setup script for Record Historical Immunization Task

echo "=== Setting up Record Historical Immunization Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial immunization count for this patient
echo "Recording initial immunization count for patient..."
INITIAL_IMM_COUNT=$(openemr_query "SELECT COUNT(*) FROM immunizations WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_IMM_COUNT" > /tmp/initial_immunization_count
echo "Initial immunization count for patient: $INITIAL_IMM_COUNT"

# Record total immunizations in system (for anti-gaming)
TOTAL_IMM_COUNT=$(openemr_query "SELECT COUNT(*) FROM immunizations" 2>/dev/null || echo "0")
echo "$TOTAL_IMM_COUNT" > /tmp/total_immunization_count
echo "Total immunizations in system: $TOTAL_IMM_COUNT"

# Record task start timestamp (Unix epoch seconds)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START ($(date -d @$TASK_START '+%Y-%m-%d %H:%M:%S'))"

# Also record as ISO format for easier debugging
date -Iseconds > /tmp/task_start_time_iso
echo "Task start (ISO): $(cat /tmp/task_start_time_iso)"

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

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Focus Firefox again
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take initial screenshot for audit verification
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Record Historical Immunization Task Setup Complete ==="
echo ""
echo "Task: Record a historical DTaP immunization for patient $PATIENT_NAME"
echo ""
echo "Patient Details:"
echo "  - Name: $PATIENT_NAME"
echo "  - PID: $PATIENT_PID"
echo "  - DOB: 1992-06-30"
echo ""
echo "Vaccination to Enter:"
echo "  - Vaccine: DTaP (Diphtheria, Tetanus, Pertussis)"
echo "  - Date Administered: 2019-03-15 (HISTORICAL - not today!)"
echo "  - Administered By: Outside Provider"
echo "  - Administration Site: Left Deltoid"
echo "  - Manufacturer: Sanofi Pasteur"
echo "  - Lot Number: D2894AA"
echo "  - Expiration Date: 2020-03-01"
echo "  - Notes: Historical entry - vaccine administered at Springfield Family Medicine"
echo ""
echo "Login Credentials: admin / pass"
echo ""
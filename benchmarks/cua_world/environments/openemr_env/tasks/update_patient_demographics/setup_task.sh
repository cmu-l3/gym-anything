#!/bin/bash
# Setup script for Update Patient Demographics Task

echo "=== Setting up Update Patient Demographics Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial demographics for verification (anti-gaming: detect actual changes)
echo "Recording initial demographics..."
INITIAL_DATA=$(openemr_query "SELECT street, city, state, postal_code, phone_home, phone_cell FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Initial demographics: $INITIAL_DATA"

# Parse and save initial state to JSON
INITIAL_STREET=$(echo "$INITIAL_DATA" | cut -f1)
INITIAL_CITY=$(echo "$INITIAL_DATA" | cut -f2)
INITIAL_STATE=$(echo "$INITIAL_DATA" | cut -f3)
INITIAL_POSTAL=$(echo "$INITIAL_DATA" | cut -f4)
INITIAL_PHONE_HOME=$(echo "$INITIAL_DATA" | cut -f5)
INITIAL_PHONE_CELL=$(echo "$INITIAL_DATA" | cut -f6)

# Handle NULL values
[ "$INITIAL_STREET" = "NULL" ] && INITIAL_STREET=""
[ "$INITIAL_CITY" = "NULL" ] && INITIAL_CITY=""
[ "$INITIAL_STATE" = "NULL" ] && INITIAL_STATE=""
[ "$INITIAL_POSTAL" = "NULL" ] && INITIAL_POSTAL=""
[ "$INITIAL_PHONE_HOME" = "NULL" ] && INITIAL_PHONE_HOME=""
[ "$INITIAL_PHONE_CELL" = "NULL" ] && INITIAL_PHONE_CELL=""

# Escape for JSON
INITIAL_STREET_ESC=$(echo "$INITIAL_STREET" | sed 's/"/\\"/g')
INITIAL_CITY_ESC=$(echo "$INITIAL_CITY" | sed 's/"/\\"/g')

cat > /tmp/initial_demographics.json << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_values": {
        "street": "$INITIAL_STREET_ESC",
        "city": "$INITIAL_CITY_ESC",
        "state": "$INITIAL_STATE",
        "postal_code": "$INITIAL_POSTAL",
        "phone_home": "$INITIAL_PHONE_HOME",
        "phone_cell": "$INITIAL_PHONE_CELL"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state saved to /tmp/initial_demographics.json"
cat /tmp/initial_demographics.json

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

# Take initial screenshot for audit verification
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Update Patient Demographics Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1992-06-30)"
echo ""
echo "Current Address:"
echo "  Street: $INITIAL_STREET"
echo "  City: $INITIAL_CITY"
echo "  State: $INITIAL_STATE"
echo "  ZIP: $INITIAL_POSTAL"
echo "  Home Phone: $INITIAL_PHONE_HOME"
echo "  Cell Phone: $INITIAL_PHONE_CELL"
echo ""
echo "NEW Address to Enter:"
echo "  Street: 742 Evergreen Terrace, Unit 3A"
echo "  City: Springfield"
echo "  State: MA"
echo "  ZIP: 01103"
echo "  Home Phone: 413-555-0842"
echo "  Cell Phone: 413-555-9173"
echo ""
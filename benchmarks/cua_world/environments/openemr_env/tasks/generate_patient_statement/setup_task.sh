#!/bin/bash
# Setup script for Generate Patient Statement task

echo "=== Setting up Generate Patient Statement Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (critical for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt
echo "Task start timestamp: $TASK_START"

# Target patient information
PATIENT_PID=3
PATIENT_FNAME="Jayson"
PATIENT_LNAME="Fadel"

# Ensure OpenEMR containers are running
echo "Checking OpenEMR status..."
cd /home/ga/openemr
if ! docker-compose ps 2>/dev/null | grep -q "Up"; then
    echo "Starting OpenEMR containers..."
    docker-compose up -d
    sleep 30
fi

# Wait for OpenEMR to be ready
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"
echo "Waiting for OpenEMR to be accessible..."
for i in {1..60}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$OPENEMR_URL" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "OpenEMR is ready (HTTP $HTTP_CODE)"
        break
    fi
    sleep 2
done

# Verify patient exists in database
echo "Verifying patient $PATIENT_FNAME $PATIENT_LNAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)

if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Ensure billing data exists for the patient
echo "Ensuring billing data exists for patient..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
    INSERT IGNORE INTO billing (id, date, pid, encounter, code_type, code, code_text, modifier, fee, units, billed, activity, authorized)
    VALUES 
    (NULL, '2024-01-15', $PATIENT_PID, 1, 'CPT4', '99213', 'Office Visit - Established Patient Level 3', '', 125.00, 1, 0, 1, 1),
    (NULL, '2024-02-20', $PATIENT_PID, 2, 'CPT4', '99214', 'Office Visit - Established Patient Level 4', '', 175.00, 1, 0, 1, 1),
    (NULL, '2024-03-10', $PATIENT_PID, 3, 'CPT4', '36415', 'Venipuncture - Blood Draw', '', 15.00, 1, 0, 1, 1),
    (NULL, '2024-03-10', $PATIENT_PID, 3, 'CPT4', '80053', 'Comprehensive Metabolic Panel', '', 45.00, 1, 0, 1, 1);
" 2>/dev/null || echo "Billing records may already exist"

# Record initial billing count for this patient
INITIAL_BILLING_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM billing WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_BILLING_COUNT" > /tmp/initial_billing_count.txt
echo "Initial billing record count: $INITIAL_BILLING_COUNT"

# Calculate total charges for patient
TOTAL_CHARGES=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COALESCE(SUM(fee), 0) FROM billing WHERE pid=$PATIENT_PID AND activity=1" 2>/dev/null || echo "0")
echo "$TOTAL_CHARGES" > /tmp/expected_total_charges.txt
echo "Total charges for patient: \$$TOTAL_CHARGES"

# Record initial log count for tracking access
INITIAL_LOG_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM log" 2>/dev/null || echo "0")
echo "$INITIAL_LOG_COUNT" > /tmp/initial_log_count.txt

# Kill any existing Firefox instances
echo "Stopping any existing Firefox instances..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox with OpenEMR login page
echo "Launching Firefox with OpenEMR..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Focus and maximize Firefox window
sleep 2
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Focusing Firefox window: $WID"
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any Firefox first-run dialogs
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for evidence
echo "Capturing initial screenshot..."
sleep 1
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Generate Patient Statement Task Setup Complete ==="
echo ""
echo "TASK: Generate Patient Account Statement"
echo "=========================================="
echo ""
echo "Patient: $PATIENT_FNAME $PATIENT_LNAME (PID: $PATIENT_PID)"
echo "DOB: 1992-06-30"
echo "Total Charges: \$$TOTAL_CHARGES"
echo ""
echo "Login Credentials:"
echo "  Username: admin"
echo "  Password: pass"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR"
echo "  2. Search for and select patient '$PATIENT_FNAME $PATIENT_LNAME'"
echo "  3. Navigate to Fees/Billing section"
echo "  4. View or generate the patient statement"
echo ""
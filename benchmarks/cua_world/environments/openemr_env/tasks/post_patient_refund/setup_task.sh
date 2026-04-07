#!/bin/bash
set -e

echo "=== Setting up Post Patient Refund Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Target patient details
PATIENT_FNAME="Marcus"
PATIENT_LNAME="Cartwright"
PATIENT_DOB="1972-02-14"

# Ensure OpenEMR containers are running
echo "Verifying OpenEMR is running..."
cd /home/ga/openemr
docker-compose ps | grep -q "Up" || docker-compose up -d
sleep 3

# Wait for OpenEMR to be ready
echo "Waiting for OpenEMR to be ready..."
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/interface/login/login.php?site=default" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "OpenEMR ready (HTTP $HTTP_CODE)"
        break
    fi
    sleep 2
done

# Check if patient Marcus Cartwright exists, create if not
echo "Verifying patient $PATIENT_FNAME $PATIENT_LNAME exists..."
PATIENT_EXISTS=$(openemr_query "SELECT COUNT(*) FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME'" 2>/dev/null || echo "0")

if [ "$PATIENT_EXISTS" -eq 0 ]; then
    echo "Creating patient $PATIENT_FNAME $PATIENT_LNAME..."
    openemr_query "INSERT INTO patient_data (fname, lname, DOB, sex, street, city, state, postal_code, phone_cell, email, date) VALUES ('$PATIENT_FNAME', '$PATIENT_LNAME', '$PATIENT_DOB', 'Male', '742 Evergreen Terrace', 'Springfield', 'MA', '01103', '555-0142', 'marcus.cartwright@email.com', NOW())"
    echo "Patient created successfully"
else
    echo "Patient already exists"
fi

# Get patient PID
PATIENT_PID=$(openemr_query "SELECT pid FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME' LIMIT 1" 2>/dev/null)
echo "Patient PID: $PATIENT_PID"
echo "$PATIENT_PID" > /tmp/target_patient_pid.txt

# Ensure patient has at least one encounter for realistic billing scenario
ENCOUNTER_EXISTS=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
if [ "$ENCOUNTER_EXISTS" -eq 0 ]; then
    echo "Creating sample encounter for billing context..."
    ENCOUNTER_NUM=$((RANDOM + 100000))
    openemr_query "INSERT INTO form_encounter (date, reason, facility_id, pid, encounter, sensitivity, billing_note) VALUES (DATE_SUB(NOW(), INTERVAL 30 DAY), 'Office Visit', 3, $PATIENT_PID, $ENCOUNTER_NUM, 'normal', 'Routine checkup')"
    echo "Encounter created"
fi

# Record initial billing state for comparison (anti-gaming)
echo "Recording initial billing state..."
INITIAL_AR_COUNT=$(openemr_query "SELECT COUNT(*) FROM ar_activity WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
INITIAL_PAY_COUNT=$(openemr_query "SELECT COUNT(*) FROM payments WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "$INITIAL_AR_COUNT" > /tmp/initial_ar_count.txt
echo "$INITIAL_PAY_COUNT" > /tmp/initial_pay_count.txt
echo "Initial AR activity count: $INITIAL_AR_COUNT"
echo "Initial payments count: $INITIAL_PAY_COUNT"

# Get most recent transaction IDs to detect new entries
LATEST_AR_ID=$(openemr_query "SELECT COALESCE(MAX(sequence_no), 0) FROM ar_activity" 2>/dev/null || echo "0")
LATEST_PAY_ID=$(openemr_query "SELECT COALESCE(MAX(id), 0) FROM payments" 2>/dev/null || echo "0")
echo "$LATEST_AR_ID" > /tmp/latest_ar_id.txt
echo "$LATEST_PAY_ID" > /tmp/latest_pay_id.txt
echo "Latest AR sequence: $LATEST_AR_ID, Latest payment ID: $LATEST_PAY_ID"

# Kill any existing Firefox instances for clean start
echo "Preparing Firefox..."
pkill -f firefox || true
sleep 2

# Launch Firefox to OpenEMR login page
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window
echo "Waiting for Firefox window..."
wait_for_window "firefox\|mozilla\|OpenEMR" 30

# Maximize and focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    echo "Firefox window found: $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for audit
echo "Taking initial screenshot..."
take_screenshot /tmp/task_initial.png
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
fi

echo ""
echo "=== Post Patient Refund Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_FNAME $PATIENT_LNAME (PID: $PATIENT_PID)"
echo "DOB: $PATIENT_DOB"
echo ""
echo "TASK INSTRUCTIONS:"
echo "  1. Log in to OpenEMR (username: admin, password: pass)"
echo "  2. Search for and select patient Marcus Cartwright"
echo "  3. Navigate to Fees/Billing section"
echo "  4. Post a refund of \$45.00 (negative amount)"
echo "  5. Reference: REF-2024-001"
echo "  6. Note: 'Insurance overpayment - credit balance refund'"
echo "  7. Save the transaction"
echo ""
#!/bin/bash
# Setup script for Document Referral Outcome Task

echo "=== Setting up Document Referral Outcome Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient - Domingo Kiehn
PATIENT_FNAME="Domingo"
PATIENT_LNAME="Kiehn"
PATIENT_DOB="1960-02-08"

# First, find the patient in the database
echo "Finding patient $PATIENT_FNAME $PATIENT_LNAME..."
PATIENT_DATA=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME' LIMIT 1" 2>/dev/null)

if [ -z "$PATIENT_DATA" ]; then
    echo "Patient not found, searching by DOB..."
    PATIENT_DATA=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE DOB='$PATIENT_DOB' LIMIT 1" 2>/dev/null)
fi

if [ -z "$PATIENT_DATA" ]; then
    echo "Patient not found by name or DOB. Listing available patients..."
    openemr_query "SELECT pid, fname, lname, DOB FROM patient_data LIMIT 10" 2>/dev/null
    echo ""
    echo "Creating test patient for task..."
    # Insert patient if not exists
    openemr_query "INSERT INTO patient_data (fname, lname, DOB, sex, street, city, state, postal_code) VALUES ('$PATIENT_FNAME', '$PATIENT_LNAME', '$PATIENT_DOB', 'Male', '123 Test Street', 'Boston', 'MA', '02101')" 2>/dev/null || true
    PATIENT_DATA=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME' LIMIT 1" 2>/dev/null)
fi

# Parse patient PID
PATIENT_PID=$(echo "$PATIENT_DATA" | cut -f1)
echo "Patient found: PID=$PATIENT_PID"
echo "$PATIENT_PID" > /tmp/target_patient_pid

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Check for existing referrals and remove any pending cardiology referrals to start fresh
echo "Checking for existing referrals..."
EXISTING_REFERRALS=$(openemr_query "SELECT id, title, refer_to FROM transactions WHERE pid=$PATIENT_PID AND title LIKE '%Referral%'" 2>/dev/null)
echo "Existing referrals: $EXISTING_REFERRALS"

# Delete any existing cardiology referrals for clean test
openemr_query "DELETE FROM transactions WHERE pid=$PATIENT_PID AND title LIKE '%Referral%' AND refer_to LIKE '%Cardiology%'" 2>/dev/null || true

# Create a pending cardiology referral for the patient
echo "Creating pending cardiology referral..."
REFERRAL_DATE=$(date +%Y-%m-%d)

# Insert the pending referral into transactions table
openemr_query "INSERT INTO transactions (date, title, body, pid, user, groupname, refer_to, refer_from, refer_date, refer_diag, refer_risk_level) VALUES (NOW(), 'Referral', '', $PATIENT_PID, 'admin', 'Default', 'Cardiology', 'Primary Care', '2024-01-15', 'Cardiac evaluation for uncontrolled hypertension', 'Medium')" 2>/dev/null

# Verify referral was created
NEW_REFERRAL=$(openemr_query "SELECT id, pid, title, refer_to, refer_diag, reply_date FROM transactions WHERE pid=$PATIENT_PID AND title LIKE '%Referral%' AND refer_to LIKE '%Cardiology%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
if [ -n "$NEW_REFERRAL" ]; then
    REFERRAL_ID=$(echo "$NEW_REFERRAL" | cut -f1)
    echo "Pending referral created with ID: $REFERRAL_ID"
    echo "$REFERRAL_ID" > /tmp/initial_referral_id
else
    echo "WARNING: Failed to create referral"
fi

# Record initial referral state
echo "Recording initial referral state..."
INITIAL_STATE=$(openemr_query "SELECT id, reply_date, body, refer_reply_mail FROM transactions WHERE pid=$PATIENT_PID AND title LIKE '%Referral%' AND refer_to LIKE '%Cardiology%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
echo "$INITIAL_STATE" > /tmp/initial_referral_state
echo "Initial state: $INITIAL_STATE"

# Record initial referral count for this patient
INITIAL_REFERRAL_COUNT=$(openemr_query "SELECT COUNT(*) FROM transactions WHERE pid=$PATIENT_PID AND title LIKE '%Referral%'" 2>/dev/null || echo "0")
echo "$INITIAL_REFERRAL_COUNT" > /tmp/initial_referral_count
echo "Initial referral count: $INITIAL_REFERRAL_COUNT"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill existing Firefox for clean state
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
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
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Document Referral Outcome Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_FNAME $PATIENT_LNAME (PID: $PATIENT_PID)"
echo "Referral: Cardiology - Pending"
echo "Referral ID: $(cat /tmp/initial_referral_id 2>/dev/null || echo 'unknown')"
echo ""
echo "Task: Update the referral with specialist consultation results"
echo ""
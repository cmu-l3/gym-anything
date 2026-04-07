#!/bin/bash
# Setup script for Add Secondary Insurance task

echo "=== Setting up Add Secondary Insurance Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=6
PATIENT_NAME="Jacklyn Kulas"

# Record task start time for anti-gaming verification
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

# Ensure Blue Cross Blue Shield exists in insurance_companies table
echo "Ensuring Blue Cross Blue Shield insurance company exists..."
BCBS_EXISTS=$(openemr_query "SELECT id FROM insurance_companies WHERE name LIKE '%Blue Cross Blue Shield%' LIMIT 1" 2>/dev/null)
if [ -z "$BCBS_EXISTS" ]; then
    echo "Adding Blue Cross Blue Shield to insurance companies..."
    openemr_query "INSERT INTO insurance_companies (name, attn, cms_id, city, state, zip) VALUES ('Blue Cross Blue Shield', 'Claims Department', 'BCBS001', 'Boston', 'MA', '02101')" 2>/dev/null
    BCBS_ID=$(openemr_query "SELECT id FROM insurance_companies WHERE name='Blue Cross Blue Shield' LIMIT 1" 2>/dev/null)
    echo "Created Blue Cross Blue Shield with id: $BCBS_ID"
else
    echo "Blue Cross Blue Shield already exists with id: $BCBS_EXISTS"
fi

# Remove any existing secondary insurance for this patient (clean slate)
echo "Removing any existing secondary insurance for patient $PATIENT_PID..."
openemr_query "DELETE FROM insurance_data WHERE pid=$PATIENT_PID AND type='secondary'" 2>/dev/null
echo "Secondary insurance cleared."

# Ensure primary insurance exists (Medicare Part B)
echo "Ensuring primary insurance exists..."
PRIMARY_EXISTS=$(openemr_query "SELECT id FROM insurance_data WHERE pid=$PATIENT_PID AND type='primary' LIMIT 1" 2>/dev/null)
if [ -z "$PRIMARY_EXISTS" ]; then
    echo "Adding primary insurance (Medicare Part B)..."
    # Get or create Medicare insurance company
    MEDICARE_ID=$(openemr_query "SELECT id FROM insurance_companies WHERE name LIKE '%Medicare%' LIMIT 1" 2>/dev/null)
    if [ -z "$MEDICARE_ID" ]; then
        openemr_query "INSERT INTO insurance_companies (name, attn, cms_id, city, state, zip) VALUES ('Medicare Part B', 'Claims', 'MEDICARE', 'Washington', 'DC', '20001')" 2>/dev/null
        MEDICARE_ID=$(openemr_query "SELECT id FROM insurance_companies WHERE name='Medicare Part B' LIMIT 1" 2>/dev/null)
    fi
    
    openemr_query "INSERT INTO insurance_data (pid, type, provider, plan_name, policy_number, group_number, subscriber_relationship, date) VALUES ($PATIENT_PID, 'primary', $MEDICARE_ID, 'Medicare Part B', '1EG4-TE5-MK72', 'MEDICARE-B', 'self', '2020-01-01')" 2>/dev/null
    echo "Primary insurance added."
else
    echo "Primary insurance already exists with id: $PRIMARY_EXISTS"
fi

# Record initial state for verification
echo "Recording initial state..."
INITIAL_PRIMARY=$(openemr_query "SELECT COUNT(*) FROM insurance_data WHERE pid=$PATIENT_PID AND type='primary'" 2>/dev/null || echo "0")
INITIAL_SECONDARY=$(openemr_query "SELECT COUNT(*) FROM insurance_data WHERE pid=$PATIENT_PID AND type='secondary'" 2>/dev/null || echo "0")
INITIAL_TOTAL=$(openemr_query "SELECT COUNT(*) FROM insurance_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "$INITIAL_PRIMARY" > /tmp/initial_primary_count.txt
echo "$INITIAL_SECONDARY" > /tmp/initial_secondary_count.txt
echo "$INITIAL_TOTAL" > /tmp/initial_total_insurance_count.txt

echo "Initial insurance counts - Primary: $INITIAL_PRIMARY, Secondary: $INITIAL_SECONDARY, Total: $INITIAL_TOTAL"

# Show current insurance for debugging
echo ""
echo "=== Current insurance records for patient ==="
openemr_query "SELECT id, type, policy_number, group_number FROM insurance_data WHERE pid=$PATIENT_PID" 2>/dev/null
echo "============================================="
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
echo "=== Add Secondary Insurance Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "DOB: 1948-10-04"
echo ""
echo "Current Insurance:"
echo "  - Primary: Medicare Part B (exists)"
echo "  - Secondary: NONE (to be added)"
echo ""
echo "Secondary Insurance to Add:"
echo "  - Company: Blue Cross Blue Shield"
echo "  - Policy Number: SEC-2024-889712"
echo "  - Group Number: MEDIGAP-F"
echo "  - Subscriber: Self"
echo "  - Effective Date: 2024-01-01"
echo ""
echo "Login: admin / pass"
echo ""
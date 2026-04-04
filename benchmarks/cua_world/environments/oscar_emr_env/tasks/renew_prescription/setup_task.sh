#!/bin/bash
# Setup script for Renew Prescription task in OSCAR EMR

echo "=== Setting up Renew Prescription Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Patient Exists (Maria Garcia)
PATIENT_FNAME="Maria"
PATIENT_LNAME="Garcia"

echo "Checking for patient $PATIENT_FNAME $PATIENT_LNAME..."
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='$PATIENT_FNAME' AND last_name='$PATIENT_LNAME'" || echo "0")

if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "Seeding patient Maria Garcia..."
    # Seed patient if missing (Synthea fallback)
    oscar_query "INSERT IGNORE INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) VALUES ('$PATIENT_LNAME', '$PATIENT_FNAME', 'F', '1965', '05', '12', 'Toronto', 'ON', 'M5V 2T6', '(416) 555-0199', '999998', '9876543210', 'ON', 'AC', NOW());" 2>/dev/null || true
fi

# Get Demographic No
DEMO_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='$PATIENT_FNAME' AND last_name='$PATIENT_LNAME' LIMIT 1")
echo "Patient ID: $DEMO_NO"

# 2. Seed Initial Expiring Prescription
# We want a prescription that looks like it's about to expire or just expired.
# Drug: Metformin 500mg
# Date: 90 days ago
# Qty: 180 (90 days * 2/day)
# Repeats: 0

echo "Seeding initial Metformin prescription..."
# Clean up any existing Metformin prescriptions for this patient to ensure clean state
oscar_query "DELETE FROM drugs WHERE demographic_no='$DEMO_NO' AND (gn LIKE '%Metformin%' OR bn LIKE '%Metformin%')" 2>/dev/null || true

# Insert "old" prescription
# Dates: Written 3 months ago
RX_DATE=$(date -d "90 days ago" +%Y-%m-%d)
END_DATE=$(date -d "today" +%Y-%m-%d) # Expires today

oscar_query "INSERT INTO drugs (demographic_no, provider_no, rx_date, end_date, written_date, bn, gn, dosage, takemin, takemax, freqCode, duration, durUnit, quantity, repeat_rx, archived, script_no, route) VALUES ('$DEMO_NO', '999998', '$RX_DATE', '$END_DATE', '$RX_DATE', 'Metformin', 'Metformin', '500mg', '1', '1', 'BID', '90', 'D', '180', '0', '0', '0', 'PO');"

echo "Seeded Metformin Rx from $RX_DATE (expires $END_DATE)"

# 3. Record Initial State for Verification
# We need the max ID of the drugs table to detect NEW records later
INITIAL_MAX_ID=$(oscar_query "SELECT MAX(id) FROM drugs" || echo "0")
# Handle empty table case
if [ "$INITIAL_MAX_ID" = "NULL" ]; then INITIAL_MAX_ID=0; fi

echo "$INITIAL_MAX_ID" > /tmp/initial_drugs_max_id
echo "Initial Max Drug ID: $INITIAL_MAX_ID"
echo "$DEMO_NO" > /tmp/task_patient_id

# Record timestamp
date +%s > /tmp/task_start_timestamp

# 4. Prepare Browser
ensure_firefox_on_oscar

# 5. Capture Initial Screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Renew Prescription Setup Complete ==="
echo "Patient: Maria Garcia"
echo "Medication: Metformin 500mg (Active, 0 repeats)"
echo "Task: Renew this medication with Quantity: 90 and Repeats: 3"
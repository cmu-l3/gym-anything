#!/bin/bash
set -e
echo "=== Setting up reverse_patient_payment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is available."
        break
    fi
    sleep 2
done

# 2. Seed Data: Patient "Maria Rivera"
echo "Seeding patient Maria Rivera..."
# Check if exists, if not create
PATIENT_ID="patient_p1_P00555"
PATIENT_DOC='{
  "data": {
    "friendlyId": "P00555",
    "firstName": "Maria",
    "lastName": "Rivera",
    "sex": "Female",
    "dateOfBirth": "1985-05-15",
    "status": "Active",
    "address": "123 Oak St",
    "phone": "555-0199",
    "email": "maria.rivera@example.com",
    "patientType": "Outpatient"
  },
  "type": "patient"
}'

# We use the helper from task_utils if available, or raw curl
# Using raw curl to ensure specific ID
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_ID}" \
    -H "Content-Type: application/json" \
    -d "$PATIENT_DOC" > /dev/null || true

# 3. Seed Data: Payment Record
# We need a predictable ID to verify its deletion later
PAYMENT_ID="payment_p1_seeded_123"
PAYMENT_DOC='{
  "data": {
    "patient": "Maria Rivera (P00555)",
    "amount": 150,
    "paymentDate": "2023-10-25T10:00:00.000Z",
    "paymentType": "Cash",
    "referenceNumber": "ERR-123",
    "status": "Paid"
  },
  "type": "payment"
}'

echo "Seeding erroneous payment..."
# Force create/overwrite
REV=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PAYMENT_ID}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")
if [ -n "$REV" ]; then
    # Update existing
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PAYMENT_ID}" \
        -H "Content-Type: application/json" \
        -d "{\"_rev\": \"$REV\", \"data\": {\"patient\": \"Maria Rivera (P00555)\", \"amount\": 150, \"paymentDate\": \"2023-10-25T10:00:00.000Z\", \"paymentType\": \"Cash\", \"status\": \"Paid\"}, \"type\": \"payment\"}" > /dev/null
else
    # Create new
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PAYMENT_ID}" \
        -H "Content-Type: application/json" \
        -d "$PAYMENT_DOC" > /dev/null
fi

# Verify seeding success
if curl -s -f "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PAYMENT_ID}" > /dev/null; then
    echo "Payment seeded successfully."
else
    echo "ERROR: Failed to seed payment."
    exit 1
fi

# 4. Browser Setup
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Navigate to Dashboard to start
navigate_firefox_to "http://localhost:3000/"

# Wait for DB sync
wait_for_db_ready

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
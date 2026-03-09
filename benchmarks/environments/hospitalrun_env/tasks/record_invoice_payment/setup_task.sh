#!/bin/bash
echo "=== Setting up record_invoice_payment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Seed Data: Patient, Visit, Invoice
echo "Seeding data for Maria Elena Santos..."

# Define IDs
PATIENT_ID="patient_p1_000042"
VISIT_ID="visit_p1_000042"
INVOICE_ID="invoice_p1_000042"

# Delete existing documents to ensure clean state
hr_couch_delete "$INVOICE_ID"
hr_couch_delete "$VISIT_ID"
hr_couch_delete "$PATIENT_ID"

# Create Patient
PATIENT_DATA='{
  "data": {
    "friendlyId": "P00042",
    "firstName": "Maria Elena",
    "lastName": "Santos",
    "sex": "Female",
    "dateOfBirth": "1978-06-15T00:00:00.000Z",
    "patientType": "Charity",
    "phone": "555-0199",
    "address": "123 Main St, Springfield",
    "status": "Active"
  }
}'
hr_couch_put "$PATIENT_ID" "$PATIENT_DATA"

# Create Visit
VISIT_DATA='{
  "data": {
    "visitType": "Outpatient",
    "patient": "'"$PATIENT_ID"'",
    "startDate": "2025-01-10T09:00:00.000Z",
    "endDate": "2025-01-10T10:30:00.000Z",
    "examiner": "Dr. James Wilson",
    "status": "completed",
    "reasonForVisit": "General Checkup"
  }
}'
hr_couch_put "$VISIT_ID" "$VISIT_DATA"

# Create Invoice (Unpaid)
# Note: HospitalRun invoices contain lineItems and an empty payments array initially
INVOICE_DATA='{
  "data": {
    "billDate": "2025-01-10T10:00:00.000Z",
    "patient": "'"$PATIENT_ID"'",
    "visit": "'"$VISIT_ID"'",
    "paymentProfile": "private",
    "status": "billed",
    "total": 475.00,
    "paidTotal": 0.00,
    "balance": 475.00,
    "lineItems": [
      {
        "name": "Outpatient Consultation",
        "description": "General Medicine",
        "quantity": 1,
        "amount": 250.00
      },
      {
        "name": "Complete Blood Count",
        "description": "Lab",
        "quantity": 1,
        "amount": 125.00
      },
      {
        "name": "Basic Metabolic Panel",
        "description": "Lab",
        "quantity": 1,
        "amount": 100.00
      }
    ],
    "payments": []
  }
}'
hr_couch_put "$INVOICE_ID" "$INVOICE_DATA"

# Record initial revision for anti-gaming check
INITIAL_REV=$(hr_couch_get "$INVOICE_ID" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")
echo "$INITIAL_REV" > /tmp/initial_invoice_rev.txt
echo "Seeded Invoice $INVOICE_ID with rev $INITIAL_REV"

# 3. Prepare Browser
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in
wait_for_db_ready

# 4. Navigate to Billing/Invoices explicitly to help the agent start
echo "Navigating to Invoices list..."
navigate_firefox_to "http://localhost:3000/#/invoices"
sleep 5

# 5. Initial Screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state capture complete."
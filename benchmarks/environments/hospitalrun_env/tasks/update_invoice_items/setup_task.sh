#!/bin/bash
echo "=== Setting up update_invoice_items task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
wait_for_db_ready

# 2. Seed Data
echo "Seeding required data..."

# 2a. Ensure Patient Maria Santos exists
# Check if exists, if not create
if ! curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_maria_santos" | grep -q "_id"; then
    echo "Creating patient Maria Santos..."
    hr_couch_put "patient_maria_santos" '{
        "data": {
            "firstName": "Maria",
            "lastName": "Santos",
            "friendlyId": "P00003",
            "sex": "Female",
            "dateOfBirth": "1985-07-20",
            "patientType": "Outpatient",
            "phone": "555-0199",
            "address": "123 Main St"
        },
        "type": "patient"
    }'
else
    echo "Patient Maria Santos already exists."
fi

# 2b. Ensure Pricing Items exist (General Consultation and Urinalysis)
# General Consultation ($50)
hr_couch_put "pricing_gen_consult" '{
    "data": {
        "name": "General Consultation",
        "price": 50.00,
        "pricingType": "procedure",
        "category": "Consultation"
    },
    "type": "pricing"
}'

# Urinalysis ($25)
hr_couch_put "pricing_urinalysis" '{
    "data": {
        "name": "Urinalysis",
        "price": 25.00,
        "pricingType": "lab",
        "category": "Laboratory"
    },
    "type": "pricing"
}'

# 2c. Create the Draft Invoice (#INV-2024-001)
# We delete it first to ensure a clean state if re-running
hr_couch_delete "invoice_inv_2024_001"

echo "Creating initial draft invoice..."
# Note: HospitalRun invoices usually link to pricing items.
# Structure based on HospitalRun v1 invoice model.
hr_couch_put "invoice_inv_2024_001" '{
    "data": {
        "invoiceNumber": "INV-2024-001",
        "patient": "patient_maria_santos",
        "status": "Draft",
        "date": "'$(date +%Y-%m-%d)'",
        "lineItems": [
            {
                "id": "li_1",
                "name": "General Consultation",
                "description": "Standard checkup",
                "quantity": 1,
                "amount": 50.00,
                "pricingItem": "pricing_gen_consult"
            }
        ],
        "total": 50.00,
        "paymentStatus": "Unpaid"
    },
    "type": "invoice"
}'

# Record initial revision for verification comparison
INITIAL_REV=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/invoice_inv_2024_001" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")
echo "$INITIAL_REV" > /tmp/initial_invoice_rev.txt
echo "Initial Invoice Rev: $INITIAL_REV"

# 3. Prepare Browser
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Navigate to Invoices list to start
echo "Navigating to Invoices list..."
navigate_firefox_to "http://localhost:3000/#/billing/invoices"
sleep 5

# 4. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
#!/bin/bash
# Setup script for Create Private Invoice task in OSCAR EMR

echo "=== Setting up Create Private Invoice Task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Verify patient Maria Santos exists (Synthea-generated patient)
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Maria' AND last_name='Santos'" || echo "0")
if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "WARNING: Patient Maria Santos not found — seeding fallback record..."
    oscar_query "INSERT IGNORE INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) VALUES ('Santos', 'Maria', 'F', '1978', '06', '22', 'Toronto', 'ON', 'M5G 1Z8', '(416) 555-0193', '999998', '6839472581', 'ON', 'AC', NOW());" 2>/dev/null || true
fi
echo "Patient Maria Santos found."

PATIENT_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1")
echo "Patient demographic_no: $PATIENT_NO"
echo "$PATIENT_NO" > /tmp/task_patient_no

# Record initial billing count/max ID to identify new records later
INITIAL_MAX_BILL_ID=$(oscar_query "SELECT MAX(billing_no) FROM billing_master" || echo "0")
if [ "$INITIAL_MAX_BILL_ID" == "NULL" ]; then INITIAL_MAX_BILL_ID=0; fi
echo "$INITIAL_MAX_BILL_ID" > /tmp/initial_max_bill_id
echo "Initial Max Billing ID: $INITIAL_MAX_BILL_ID"

# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo ""
echo "TASK: Create a Private Invoice for Maria Santos"
echo "  Patient: Maria Santos"
echo "  Item:    Sick Note"
echo "  Cost:    $20.00"
echo "  Payer:   Direct to Patient (Private)"
echo ""
echo "  1. Log in to OSCAR (oscardoc / oscar / PIN: 1117)"
echo "  2. Search for Maria Santos"
echo "  3. Create a bill"
echo "  4. Set 'Bill To' / Payer to Patient"
echo "  5. Override fee to $20.00"
echo "  6. Save"
echo ""
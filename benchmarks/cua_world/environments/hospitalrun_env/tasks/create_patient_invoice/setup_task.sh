#!/bin/bash
set -e
echo "=== Setting up create_patient_invoice task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ─── 1. Ensure HospitalRun is running ───────────────────────────────────────
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# ─── 2. Seed Pricing Items ──────────────────────────────────────────────────
echo "Seeding pricing catalog items..."
# Pricing Item 1: X-Ray
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/pricing_p1_XRAY001" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "name": "X-Ray - Chest PA",
        "category": "Imaging",
        "price": 125.00,
        "pricingType": "Ward Pricing",
        "expenseAccount": "Imaging Services",
        "dateAdded": "2024-01-15T00:00:00.000Z"
      }
    }' > /dev/null || echo "X-Ray item might already exist"

# Pricing Item 2: Office Visit
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/pricing_p1_OFFICE001" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "name": "Office Visit - Level 3",
        "category": "Consultation",
        "price": 250.00,
        "pricingType": "Ward Pricing",
        "expenseAccount": "Professional Services",
        "dateAdded": "2024-01-15T00:00:00.000Z"
      }
    }' > /dev/null || echo "Office Visit item might already exist"

# ─── 3. Seed Patient Maria Santos ───────────────────────────────────────────
echo "Verifying/Seeding patient Maria Santos..."
# Check if exists first to avoid overwriting unless needed
PATIENT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_P00003" 2>/dev/null | grep -o "Maria")

if [ -z "$PATIENT_CHECK" ]; then
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_P00003" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "patientId": "P00003",
            "firstName": "Maria",
            "lastName": "Santos",
            "sex": "Female",
            "dateOfBirth": "1988-07-22T00:00:00.000Z",
            "address": "742 Elm Avenue",
            "city": "Boston",
            "state": "MA",
            "phone": "617-555-0134",
            "email": "maria.santos@email.com",
            "status": "Active",
            "patientType": "Outpatient"
          }
        }' > /dev/null || true
    echo "Patient Maria Santos seeded."
else
    echo "Patient Maria Santos already exists."
fi

# ─── 4. Record Initial Invoice Count ────────────────────────────────────────
# This helps detect if a new invoice was actually created
INITIAL_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
for row in data.get('rows', []):
    doc_id = row.get('id', '')
    if doc_id.startswith('invoice_'):
        count += 1
print(count)
" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_invoice_count.txt
echo "Initial invoice count: $INITIAL_COUNT"

# ─── 5. Prepare Browser ─────────────────────────────────────────────────────
echo "Launching browser..."
ensure_hospitalrun_logged_in
wait_for_db_ready

# Navigate to Billing dashboard (optional, but helpful starting point)
navigate_firefox_to "http://localhost:3000/#/billing"
sleep 5

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
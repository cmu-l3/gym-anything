#!/bin/bash
# Setup script for Link Preferred Pharmacy task in OSCAR EMR

echo "=== Setting up Link Preferred Pharmacy Task ==="

source /workspace/scripts/task_utils.sh

# 1. Verify/Create Patient Maria Santos
echo "Checking patient Maria Santos..."
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Maria' AND last_name='Santos'" || echo "0")
if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "Patient not found — creating Maria Santos..."
    # Insert realistic patient record
    oscar_query "INSERT IGNORE INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) VALUES ('Santos', 'Maria', 'F', '1978', '06', '22', 'Mississauga', 'ON', 'L5B 2C9', '905-555-0123', '999998', '5552349876', 'ON', 'AC', NOW());" 2>/dev/null || true
fi

PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1")
echo "Patient ID: $PATIENT_ID"

# 2. Verify/Create Pharmacy "Rexall Pharma Plus"
echo "Checking pharmacy Rexall Pharma Plus..."
PHARMACY_NAME="Rexall Pharma Plus"
PHARMACY_COUNT=$(oscar_query "SELECT COUNT(*) FROM pharmacy WHERE name='$PHARMACY_NAME'" || echo "0")

if [ "${PHARMACY_COUNT:-0}" -eq 0 ]; then
    echo "Pharmacy not found — creating Rexall Pharma Plus..."
    # Insert pharmacy record
    oscar_query "INSERT INTO pharmacy (name, address_line1, city, province, postal, telephone, fax, email) VALUES ('$PHARMACY_NAME', '123 Main St', 'Mississauga', 'ON', 'L5B 1J2', '905-555-0199', '905-555-0198', 'pharmacy@rexall.example.com');" 2>/dev/null || true
fi

PHARMACY_ID=$(oscar_query "SELECT pharmacyid FROM pharmacy WHERE name='$PHARMACY_NAME' LIMIT 1")
echo "Pharmacy ID: $PHARMACY_ID"

# 3. CRITICAL: Ensure NO link exists initially (Clean State)
echo "Clearing any existing links between Patient $PATIENT_ID and Pharmacy $PHARMACY_ID..."
oscar_query "DELETE FROM demographicPharmacy WHERE demographic_no='$PATIENT_ID' AND pharmacyid='$PHARMACY_ID'" 2>/dev/null || true

# 4. Record task start data
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "$PATIENT_ID" > /tmp/target_patient_id
echo "$PHARMACY_ID" > /tmp/target_pharmacy_id

# 5. Launch Firefox
ensure_firefox_on_oscar

# 6. Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Patient: Maria Santos (ID: $PATIENT_ID)"
echo "Pharmacy: Rexall Pharma Plus (ID: $PHARMACY_ID)"
echo "Goal: Create a link in demographicPharmacy table"
#!/bin/bash
# Setup script for Prescribe Medication task in OSCAR EMR

echo "=== Setting up Prescribe Medication Task ==="

source /workspace/scripts/task_utils.sh

# Verify patient Agnes Miller exists (Synthea-generated patient)
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Agnes' AND last_name='Miller'" || echo "0")
if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "WARNING: Patient Agnes Miller not found — seeding fallback record..."
    oscar_query "INSERT IGNORE INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) VALUES ('Miller', 'Agnes', 'F', '1987', '05', '16', 'Grafton', 'ON', 'M5V 1A1', '(416) 555-0334', '999998', '8011142391', 'ON', 'AC', NOW());" 2>/dev/null || true
fi
echo "Patient Agnes Miller found."

PATIENT_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Agnes' AND last_name='Miller' LIMIT 1")
echo "Patient demographic_no: $PATIENT_NO"

# Remove any existing Amoxicillin prescription for Agnes Miller (clean slate)
oscar_query "DELETE FROM drugs WHERE demographic_no='$PATIENT_NO' AND GN LIKE '%Amoxicillin%'" 2>/dev/null || true

# Record timestamp for anti-gaming
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Record initial drug count for this patient
INITIAL_DRUG_COUNT=$(oscar_query "SELECT COUNT(*) FROM drugs WHERE demographic_no='$PATIENT_NO'" || echo "0")
echo "$INITIAL_DRUG_COUNT" > /tmp/initial_drug_count
echo "$PATIENT_NO" > /tmp/task_patient_no

echo "Initial drug count for Miller: $INITIAL_DRUG_COUNT"

# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Prescribe Medication Task Setup Complete ==="
echo ""
echo "TASK: Prescribe Amoxicillin for patient Agnes Miller"
echo "  Patient:   Agnes Miller (DOB: 1987, already registered)"
echo "  Drug:      Amoxicillin 500mg"
echo "  Route:     PO (oral)"
echo "  Frequency: TID (3 times daily)"
echo "  Duration:  10 days"
echo "  Quantity:  30 tablets"
echo ""
echo "  1. Log in to OSCAR (oscardoc / oscar / PIN: 1117)"
echo "  2. Find Agnes Miller's chart via Search"
echo "  3. Go to Rx (prescriptions) section in the chart"
echo "  4. Add the new Amoxicillin prescription"
echo ""

#!/bin/bash
# Setup script for Medication Review and Allergy task in OSCAR EMR
# Patient: Fatima Al-Hassan (DOB: 1978-08-09)

echo "=== Setting up Medication Review and Allergy Task ==="

source /workspace/scripts/task_utils.sh

# Verify patient Fatima Al-Hassan exists
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Fatima' AND last_name='Al-Hassan'" || echo "0")
if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "ERROR: Patient Fatima Al-Hassan not found in database"
    exit 1
fi
echo "Patient Fatima Al-Hassan confirmed."

PATIENT_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Fatima' AND last_name='Al-Hassan' LIMIT 1")
echo "Patient demographic_no: $PATIENT_NO"
echo "$PATIENT_NO" > /tmp/task_patient_no_medreview

# Clean up any pre-existing medications for Fatima
oscar_query "DELETE FROM drugs WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared any pre-existing medications for Fatima Al-Hassan."

# Clean up any pre-existing allergies for Fatima
oscar_query "DELETE FROM allergies WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared any pre-existing allergies for Fatima Al-Hassan."

# Seed the "incorrectly entered" Amiodarone prescription (active, archived=0)
# This is the erroneous medication the agent must discontinue
# Use SELECT FROM demographic pattern (same as seed_patients.sql) to avoid NOT NULL constraint issues
oscar_query "INSERT INTO drugs
    (demographic_no, provider_no, rx_date, end_date, GN, BN, dosage, route, freqcode,
     duration, durunit, quantity, \`repeat\`, archived, lastUpdateDate, position, dispenseInternal)
SELECT d.demographic_no, '999998', DATE_SUB(CURDATE(), INTERVAL 14 DAY), '0001-01-01',
       'Amiodarone', 'Cordarone', '200mg', 'PO', 'od',
       '0', 'd', '0', 0, 0, NOW(), 0, 0
FROM demographic d WHERE d.first_name='Fatima' AND d.last_name='Al-Hassan';" 2>/dev/null || true
echo "Seeded erroneous Amiodarone prescription for Fatima Al-Hassan."

# Record baseline counts
INITIAL_DRUG_COUNT=$(oscar_query "SELECT COUNT(*) FROM drugs WHERE demographic_no='$PATIENT_NO' AND archived=0" || echo "0")
echo "$INITIAL_DRUG_COUNT" > /tmp/initial_drug_count_medreview
echo "Initial drug count: $INITIAL_DRUG_COUNT (should be 1 for Amiodarone)"

INITIAL_ALLERGY_COUNT=$(oscar_query "SELECT COUNT(*) FROM allergies WHERE demographic_no='$PATIENT_NO' AND archived=0" || echo "0")
echo "$INITIAL_ALLERGY_COUNT" > /tmp/initial_allergy_count_medreview
echo "Initial allergy count: $INITIAL_ALLERGY_COUNT (should be 0)"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Medication Review and Allergy Task Setup Complete ==="
echo "Patient: Fatima Al-Hassan (DOB: August 9, 1978)"
echo "  - Amiodarone 200mg is INCORRECTLY in her medication list (needs to be archived)"
echo "  - ASA allergy needs to be added (reaction: GI upset, severity: Moderate)"
echo "  - Metformin 500mg BID needs to be prescribed"
echo ""

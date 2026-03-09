#!/bin/bash
# Setup script for Add Allergy task in OSCAR EMR

echo "=== Setting up Add Allergy Task ==="

source /workspace/scripts/task_utils.sh

# Verify patient Eliseo Nader exists (Synthea-generated patient)
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Eliseo' AND last_name='Nader'" || echo "0")
if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "WARNING: Patient Eliseo Nader not found — seeding fallback record..."
    oscar_query "INSERT IGNORE INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) VALUES ('Nader', 'Eliseo', 'M', '1981', '12', '27', 'Revere', 'ON', 'M5V 1A1', '(416) 555-0720', '999998', '1826292004', 'ON', 'AC', NOW());" 2>/dev/null || true
fi
echo "Patient Eliseo Nader found."

PATIENT_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Eliseo' AND last_name='Nader' LIMIT 1")
echo "Patient demographic_no: $PATIENT_NO"

# Remove any pre-existing Codeine allergy for clean test
oscar_query "DELETE FROM allergies WHERE demographic_no='$PATIENT_NO' AND DESCRIPTION LIKE '%Codeine%'" 2>/dev/null || true
echo "Cleaned up any pre-existing Codeine allergy entry."

# Record timestamp for anti-gaming
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "$PATIENT_NO" > /tmp/task_patient_no

# Record initial allergy count
INITIAL_ALLERGY_COUNT=$(oscar_query "SELECT COUNT(*) FROM allergies WHERE demographic_no='$PATIENT_NO'" || echo "0")
echo "$INITIAL_ALLERGY_COUNT" > /tmp/initial_allergy_count
echo "Initial allergy count for Nader: $INITIAL_ALLERGY_COUNT"

# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Add Allergy Task Setup Complete ==="
echo ""
echo "TASK: Add a Codeine allergy for patient Eliseo Nader"
echo "  Patient:  Eliseo Nader (DOB: 1981, already registered)"
echo "  Allergen: Codeine"
echo "  Reaction: Nausea and vomiting"
echo "  Severity: Moderate"
echo ""
echo "  1. Log in to OSCAR (oscardoc / oscar / PIN: 1117)"
echo "  2. Search for and open Eliseo Nader's chart"
echo "  3. Find the allergy/CPP section"
echo "  4. Add the Codeine allergy with reaction and severity"
echo "  5. Save"
echo ""

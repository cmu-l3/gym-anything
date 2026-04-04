#!/bin/bash
# Setup script for Multi-Feature Encounter task in OSCAR EMR
# Patient: Robert MacPherson (DOB: 1948-09-17)

echo "=== Setting up Multi-Feature Encounter Task ==="

source /workspace/scripts/task_utils.sh

# Verify patient Robert MacPherson exists
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Robert' AND last_name='MacPherson'" || echo "0")
if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "ERROR: Patient Robert MacPherson not found in database"
    exit 1
fi
echo "Patient Robert MacPherson confirmed."

PATIENT_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Robert' AND last_name='MacPherson' LIMIT 1")
echo "Patient demographic_no: $PATIENT_NO"
echo "$PATIENT_NO" > /tmp/task_patient_no_multi

# Clean up any pre-existing measurements for Robert
oscar_query "DELETE FROM measurements WHERE demographicNo='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared any pre-existing measurements for Robert MacPherson."

# Clean up any pre-existing medications for Robert
oscar_query "DELETE FROM drugs WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared any pre-existing medications for Robert MacPherson."

# Clean up any pre-existing ticklers for Robert
oscar_query "DELETE FROM tickler WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared any pre-existing ticklers for Robert MacPherson."

# Seed an OPEN tickler for Robert (the one the agent must resolve)
# This represents an overdue annual labs reminder
oscar_query "INSERT INTO tickler
    (demographic_no, message, status, creator, task_assigned_to,
     service_date, priority, update_date)
VALUES
    ('$PATIENT_NO',
     'Annual labs due: fasting glucose and lipid panel — order if not done',
     'A', '999998', '999998',
     DATE_SUB(CURDATE(), INTERVAL 1 MONTH), 'Normal', NOW());" 2>/dev/null || true
echo "Seeded open tickler for Robert MacPherson (annual labs reminder)."

# Record initial tickler no for later comparison
TICKLER_NO=$(oscar_query "SELECT tickler_no FROM tickler WHERE demographic_no='$PATIENT_NO' AND status='A' ORDER BY tickler_no DESC LIMIT 1" || echo "")
echo "$TICKLER_NO" > /tmp/task_tickler_no_multi
echo "Seeded tickler_no: $TICKLER_NO"

# Record baseline counts
INITIAL_MEASUREMENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM measurements WHERE demographicNo='$PATIENT_NO'" || echo "0")
echo "$INITIAL_MEASUREMENT_COUNT" > /tmp/initial_measurement_count_multi

INITIAL_DRUG_COUNT=$(oscar_query "SELECT COUNT(*) FROM drugs WHERE demographic_no='$PATIENT_NO' AND archived=0" || echo "0")
echo "$INITIAL_DRUG_COUNT" > /tmp/initial_drug_count_multi

INITIAL_TICKLER_STATUS=$(oscar_query "SELECT status FROM tickler WHERE demographic_no='$PATIENT_NO' ORDER BY tickler_no DESC LIMIT 1" || echo "A")
echo "$INITIAL_TICKLER_STATUS" > /tmp/initial_tickler_status_multi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

echo "Baseline: measurements=$INITIAL_MEASUREMENT_COUNT, drugs=$INITIAL_DRUG_COUNT, tickler_status=$INITIAL_TICKLER_STATUS"

# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Multi-Feature Encounter Task Setup Complete ==="
echo "Patient: Robert MacPherson (DOB: September 17, 1948)"
echo "Required:"
echo "  1. Record BP measurement: 158/92 mmHg"
echo "  2. Prescribe Ramipril 10mg OD"
echo "  3. Resolve open tickler (tickler_no: $TICKLER_NO)"
echo ""

#!/bin/bash
# Setup script for Complete Patient Profile task in OSCAR EMR
# Patient: Jean-Pierre Bouchard (DOB: 1965-06-30)

echo "=== Setting up Complete Patient Profile Task ==="

source /workspace/scripts/task_utils.sh

# Verify patient Jean-Pierre Bouchard exists
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Jean-Pierre' AND last_name='Bouchard'" || echo "0")
if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "ERROR: Patient Jean-Pierre Bouchard not found in database"
    exit 1
fi
echo "Patient Jean-Pierre Bouchard confirmed."

PATIENT_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Jean-Pierre' AND last_name='Bouchard' LIMIT 1")
echo "Patient demographic_no: $PATIENT_NO"
echo "$PATIENT_NO" > /tmp/task_patient_no_profile

# Clean up any pre-existing allergies for Jean-Pierre (ensure clean baseline)
oscar_query "DELETE FROM allergies WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared any pre-existing allergies for Jean-Pierre Bouchard."

# Clean up any pre-existing medications for Jean-Pierre
oscar_query "DELETE FROM drugs WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared any pre-existing medications for Jean-Pierre Bouchard."

# Record baseline counts (should be 0 after cleanup)
INITIAL_ALLERGY_COUNT=$(oscar_query "SELECT COUNT(*) FROM allergies WHERE demographic_no='$PATIENT_NO'" || echo "0")
echo "$INITIAL_ALLERGY_COUNT" > /tmp/initial_allergy_count_profile

INITIAL_DRUG_COUNT=$(oscar_query "SELECT COUNT(*) FROM drugs WHERE demographic_no='$PATIENT_NO' AND archived=0" || echo "0")
echo "$INITIAL_DRUG_COUNT" > /tmp/initial_drug_count_profile

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

echo "Baseline: allergies=$INITIAL_ALLERGY_COUNT, medications=$INITIAL_DRUG_COUNT"

# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Complete Patient Profile Task Setup Complete ==="
echo "Patient: Jean-Pierre Bouchard (DOB: June 30, 1965)"
echo "Required: Add Penicillin allergy (Severe), Sulfa allergy (Moderate),"
echo "          Add Metformin 500mg BID, Ramipril 10mg OD"
echo ""

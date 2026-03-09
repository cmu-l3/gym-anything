#!/bin/bash
# Setup script for Record Vitals and Note task in OSCAR EMR
# Patient: Maria Santos (DOB: 1994-04-27)

echo "=== Setting up Record Vitals and Note Task ==="

source /workspace/scripts/task_utils.sh

# Verify patient Maria Santos exists
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Maria' AND last_name='Santos'" || echo "0")
if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "ERROR: Patient Maria Santos not found in database"
    exit 1
fi
echo "Patient Maria Santos confirmed."

PATIENT_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1")
echo "Patient demographic_no: $PATIENT_NO"
echo "$PATIENT_NO" > /tmp/task_patient_no_vitals

# Clean up any pre-existing measurements for Maria Santos (ensure clean baseline)
oscar_query "DELETE FROM measurements WHERE demographicNo='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared any pre-existing measurements for Maria Santos."

# Clean up any pre-existing encounter notes for Maria Santos
oscar_query "DELETE FROM casemgmt_note WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared any pre-existing encounter notes for Maria Santos."

# Record baseline counts (should be 0 after cleanup)
INITIAL_MEASUREMENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM measurements WHERE demographicNo='$PATIENT_NO'" || echo "0")
echo "$INITIAL_MEASUREMENT_COUNT" > /tmp/initial_measurement_count

INITIAL_NOTE_COUNT=$(oscar_query "SELECT COUNT(*) FROM casemgmt_note WHERE demographic_no='$PATIENT_NO' AND archived=0" || echo "0")
echo "$INITIAL_NOTE_COUNT" > /tmp/initial_note_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

echo "Baseline: measurements=$INITIAL_MEASUREMENT_COUNT, notes=$INITIAL_NOTE_COUNT"

# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Record Vitals and Note Task Setup Complete ==="
echo "Patient: Maria Santos (DOB: April 27, 1994)"
echo "Required: Record BP 118/76, Weight 63 kg, Height 167 cm, and write encounter note"
echo ""

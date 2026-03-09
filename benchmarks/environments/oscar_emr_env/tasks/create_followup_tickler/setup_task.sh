#!/bin/bash
# Setup script for Create Followup Tickler task in OSCAR EMR
# Patient: Thomas Bergmann (DOB: 1960-01-19)

echo "=== Setting up Create Followup Tickler Task ==="

source /workspace/scripts/task_utils.sh

# Verify patient Thomas Bergmann exists
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Thomas' AND last_name='Bergmann'" || echo "0")
if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "ERROR: Patient Thomas Bergmann not found in database"
    exit 1
fi
echo "Patient Thomas Bergmann confirmed."

PATIENT_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Thomas' AND last_name='Bergmann' LIMIT 1")
echo "Patient demographic_no: $PATIENT_NO"
echo "$PATIENT_NO" > /tmp/task_patient_no_tickler

# Clean up any pre-existing encounter notes for Thomas (ensure clean baseline)
oscar_query "DELETE FROM casemgmt_note WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared any pre-existing encounter notes for Thomas Bergmann."

# Clean up any pre-existing ticklers for Thomas
oscar_query "DELETE FROM tickler WHERE demographic_no='$PATIENT_NO'" 2>/dev/null || true
echo "Cleared any pre-existing ticklers for Thomas Bergmann."

# Record baseline counts (should be 0 after cleanup)
INITIAL_NOTE_COUNT=$(oscar_query "SELECT COUNT(*) FROM casemgmt_note WHERE demographic_no='$PATIENT_NO' AND archived=0" || echo "0")
echo "$INITIAL_NOTE_COUNT" > /tmp/initial_note_count_tickler

INITIAL_TICKLER_COUNT=$(oscar_query "SELECT COUNT(*) FROM tickler WHERE demographic_no='$PATIENT_NO'" || echo "0")
echo "$INITIAL_TICKLER_COUNT" > /tmp/initial_tickler_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

echo "Baseline: encounter_notes=$INITIAL_NOTE_COUNT, ticklers=$INITIAL_TICKLER_COUNT"

# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Create Followup Tickler Task Setup Complete ==="
echo "Patient: Thomas Bergmann (DOB: January 19, 1960)"
echo "Required:"
echo "  1. Encounter note mentioning chest pain, ECG changes, cardiology referral"
echo "  2. Tickler/reminder for cardiology referral follow-up"
echo ""

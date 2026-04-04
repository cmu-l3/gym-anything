#!/bin/bash
# Setup script for Initialize Antenatal Record task
set -e

echo "=== Setting up Antenatal Record Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Patient Diana Prince exists
# Using 1995-05-15 as DOB (approx 29-30 years old, appropriate for antenatal context)
FNAME="Diana"
LNAME="Prince"
DOB="1995-05-15"

echo "Checking for patient $FNAME $LNAME..."
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='$FNAME' AND last_name='$LNAME'" || echo "0")

if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "Creating patient $FNAME $LNAME..."
    # Provider 999998 is 'oscardoc'
    oscar_query "INSERT INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) VALUES ('$LNAME', '$FNAME', 'F', '1995', '05', '15', 'Themyscira', 'ON', 'M5V 1A1', '416-555-0199', '999998', '9876543210', 'ON', 'AC', NOW());"
fi

# Get Demographic No
DEMO_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='$FNAME' AND last_name='$LNAME' LIMIT 1")
echo "Patient ID: $DEMO_NO"

# 2. Clean up any existing Antenatal Records for this patient
# Table is usually 'formAR1' for Antenatal Record 1
echo "Clearing existing Antenatal Records for patient..."
oscar_query "DELETE FROM formAR1 WHERE demographic_no='$DEMO_NO'" 2>/dev/null || true

# 3. Calculate Target LMP (8 weeks ago)
# We calculate this now and save it so the export script knows exactly what 'today' was
# regardless of timezone shifts or midnight crossings during the task.
TARGET_LMP=$(date -d "8 weeks ago" +%Y-%m-%d)
echo "$TARGET_LMP" > /tmp/target_lmp.txt
echo "Target LMP (8 weeks ago): $TARGET_LMP"

# 4. Record Task Start Time
date +%s > /tmp/task_start_time.txt
echo "$DEMO_NO" > /tmp/task_patient_id.txt

# 5. Prepare Application
ensure_firefox_on_oscar

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Patient: $FNAME $LNAME"
echo "Target LMP: $TARGET_LMP"
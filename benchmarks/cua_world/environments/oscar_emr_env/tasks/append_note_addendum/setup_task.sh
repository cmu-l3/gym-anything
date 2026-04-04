#!/bin/bash
set -e
echo "=== Setting up Task: Append Note Addendum ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OSCAR is running
wait_for_oscar_http 180

TODAY=$(date +%Y-%m-%d)
echo "Today is $TODAY"

# 1. Create Patient Oliver Twist
echo "Creating patient Oliver Twist..."
PATIENT_EXISTS=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Oliver' AND last_name='Twist'" | tr -d '[:space:]')

if [ "${PATIENT_EXISTS:-0}" -eq 0 ]; then
    oscar_query "INSERT INTO demographic (
        last_name, first_name, sex, date_of_birth, year_of_birth, month_of_birth, day_of_birth,
        province, city, patient_status, date_joined,
        provider_no
    ) VALUES (
        'Twist', 'Oliver', 'M', '2010-04-01', '2010', '04', '01',
        'ON', 'London', 'AC', '$TODAY',
        '999998'
    );"
    echo "Patient created."
else
    echo "Patient already exists."
fi

# Get Demographic ID
DEMO_NO=$(get_patient_id "Oliver" "Twist")
echo "Oliver Twist Demographic ID: $DEMO_NO"
echo "$DEMO_NO" > /tmp/task_demo_no

# 2. Insert Initial Signed Note
# Note: 'uuid' is required. We generate a random one.
UUID=$(cat /proc/sys/kernel/random/uuid)
ORIGINAL_TEXT="Subjective: c/o epigastric pain. Objective: Mild tenderness."

echo "Inserting signed clinical note..."
# Clean up any existing notes for today to ensure clean state
oscar_query "DELETE FROM casemgmt_note WHERE demographic_no='$DEMO_NO' AND observation_date='$TODAY'" 2>/dev/null || true

# Insert clean note
oscar_query "INSERT INTO casemgmt_note (
    demographic_no, provider_no, note, observation_date, update_date, 
    signed, uuid, signing_provider_no, position
) VALUES (
    '$DEMO_NO', '999998', '$ORIGINAL_TEXT', '$TODAY', NOW(),
    1, '$UUID', '999998', 0
);"
echo "Clinical note inserted."

# Record initial note ID
NOTE_ID=$(oscar_query "SELECT note_id FROM casemgmt_note WHERE demographic_no='$DEMO_NO' AND observation_date='$TODAY' ORDER BY note_id DESC LIMIT 1" | tr -d '[:space:]')
echo "Note ID: $NOTE_ID"
echo "$NOTE_ID" > /tmp/task_note_id

# 3. Launch Firefox
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
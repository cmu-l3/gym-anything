#!/bin/bash
set -e
echo "=== Setting up task: update_demographics ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OSCAR is running
wait_for_oscar_http 300

# ==============================================================================
# DATA PREPARATION
# We need to ensure patient "Emily Williams" exists with SPECIFIC OLD DATA.
# If she exists, we reset her data. If not, we create her.
# ==============================================================================

TARGET_FNAME="Emily"
TARGET_LNAME="Williams"

# Check if patient exists
PATIENT_EXISTS=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='$TARGET_FNAME' AND last_name='$TARGET_LNAME' AND patient_status='AC'" | tr -d '[:space:]')

if [ "${PATIENT_EXISTS:-0}" -lt 1 ]; then
    echo "Seeding patient Emily Williams with old address..."
    # Insert with old data
    oscar_query "
        INSERT INTO demographic (
            last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
            address, city, province, postal, phone, email,
            hin, ver, roster_status, patient_status, date_joined, chart_no,
            provider_no, family_doctor
        ) VALUES (
            '$TARGET_LNAME', '$TARGET_FNAME', 'F', '1988', '07', '15',
            '78 Elm Street, Apt 4B', 'Mississauga', 'ON', 'L5B 1M5',
            '905-555-0134', '',
            '6847291058', 'AB', 'RO', 'AC', CURDATE(), '',
            '999998', '<rdohip>999998</rdohip><rd>Dr. Sarah Chen</rd>'
        );
    "
else
    echo "Emily Williams already exists. Resetting to old address..."
    # Reset to old data to ensure task is performable
    oscar_query "
        UPDATE demographic SET
            address='78 Elm Street, Apt 4B',
            city='Mississauga',
            province='ON',
            postal='L5B 1M5',
            phone='905-555-0134',
            email=''
        WHERE first_name='$TARGET_FNAME' AND last_name='$TARGET_LNAME' AND patient_status='AC';
    "
fi

# ==============================================================================
# RECORD INITIAL STATE (Anti-Gaming)
# ==============================================================================

# Get the demographic_no for verification later
DEMO_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='$TARGET_FNAME' AND last_name='$TARGET_LNAME' AND patient_status='AC' LIMIT 1" | tr -d '[:space:]')

# Helper to get field values safely
get_field() {
    oscar_query "SELECT $1 FROM demographic WHERE demographic_no='$DEMO_NO'"
}

# Capture state in JSON
python3 -c "
import json
import subprocess

def get_field(field):
    cmd = [
        'docker', 'exec', 'oscar-db', 'mysql', '-u', 'oscar', '-poscar', 'oscar', '-N', '-e',
        f\"SELECT {field} FROM demographic WHERE demographic_no='$DEMO_NO'\"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

state = {
    'demographic_no': '$DEMO_NO',
    'address': get_field('address'),
    'city': get_field('city'),
    'province': get_field('province'),
    'postal': get_field('postal'),
    'phone': get_field('phone'),
    'email': get_field('email'),
    'start_time': $(cat /tmp/task_start_time.txt)
}

with open('/tmp/initial_demographics.json', 'w') as f:
    json.dump(state, f)
"

# ==============================================================================
# UI SETUP
# ==============================================================================

# Ensure Firefox is open on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Patient: $TARGET_FNAME $TARGET_LNAME (ID: $DEMO_NO)"
echo "Reset to: 78 Elm Street, Mississauga"
#!/bin/bash
# Export script for update_patient_demographics
# Verifies the DB state matches the expected updates

echo "=== Exporting task results ==="

# 1. Capture final visual state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for the target patient
# We fetch specific fields to verify against expected values
# We select by Name/DOB to ensure we get the right record, 
# though we expect it to be PID 9000 from setup.

echo "Querying database for Eleanor Whitfield..."

# Helper to execute SQL and get JSON-like output
# using docker exec. We use -B for batch (tab separated) which is easier to parse than formatted table
DB_RESULT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e \
    "SELECT pid, firstname, lastname, address, city, state, zip, phone_home, email 
     FROM demographics 
     WHERE firstname='Eleanor' AND lastname='Whitfield' 
     LIMIT 1;" 2>/dev/null)

# 3. Process Result
FOUND="false"
PID=""
FNAME=""
LNAME=""
ADDRESS=""
CITY=""
STATE=""
ZIP=""
PHONE=""
EMAIL=""

if [ -n "$DB_RESULT" ]; then
    FOUND="true"
    # Parse tab-separated output
    # Note: If fields are empty, awk might shift columns, but NOSH requires most of these.
    # Safe parsing via read
    echo "$DB_RESULT" | while IFS=$'\t' read -r r_pid r_fname r_lname r_addr r_city r_state r_zip r_phone r_email; do
        echo "PID=$r_pid" > /tmp/parsed_patient.txt
        echo "FNAME=$r_fname" >> /tmp/parsed_patient.txt
        echo "LNAME=$r_lname" >> /tmp/parsed_patient.txt
        echo "ADDRESS=$r_addr" >> /tmp/parsed_patient.txt
        echo "CITY=$r_city" >> /tmp/parsed_patient.txt
        echo "STATE=$r_state" >> /tmp/parsed_patient.txt
        echo "ZIP=$r_zip" >> /tmp/parsed_patient.txt
        echo "PHONE=$r_phone" >> /tmp/parsed_patient.txt
        echo "EMAIL=$r_email" >> /tmp/parsed_patient.txt
    done
    
    # Reload parsed vars into current shell context
    source /tmp/parsed_patient.txt 2>/dev/null || true
fi

# 4. Check Initial State (Anti-Gaming)
# Compare current values with the ones we saved in setup_task.sh
CHANGED_COUNT=0
INITIAL_STATE_FILE="/tmp/initial_db_state.txt"
if [ -f "$INITIAL_STATE_FILE" ]; then
    # Simple grep check to see if old values are GONE
    # Initial: 45 Oak Lane, Hartford, 06103, 860-555-0147
    
    if ! grep -q "45 Oak Lane" <<< "$ADDRESS"; then ((CHANGED_COUNT++)); fi
    if ! grep -q "Hartford" <<< "$CITY"; then ((CHANGED_COUNT++)); fi
    if ! grep -q "06103" <<< "$ZIP"; then ((CHANGED_COUNT++)); fi
    if ! grep -q "860-555-0147" <<< "$PHONE"; then ((CHANGED_COUNT++)); fi
    
    echo "Detected $CHANGED_COUNT field changes from initial state."
fi

# 5. Construct JSON Result
# Using python to safely escape strings for JSON
python3 -c "
import json
import os

result = {
    'task_start': $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    'task_end': $(date +%s),
    'patient_found': $FOUND,
    'patient_data': {
        'pid': '$PID',
        'firstname': '$FNAME',
        'lastname': '$LNAME',
        'address': '$ADDRESS',
        'city': '$CITY',
        'state': '$STATE',
        'zip': '$ZIP',
        'phone': '$PHONE',
        'email': '$EMAIL'
    },
    'fields_changed_count': $CHANGED_COUNT,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 6. Safe Copy (permissions)
chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json

echo "=== Export complete ==="
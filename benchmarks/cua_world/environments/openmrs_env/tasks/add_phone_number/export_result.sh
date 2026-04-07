#!/bin/bash
# Export script for add_phone_number task
# verifies data in the database and exports result JSON

echo "=== Exporting add_phone_number result ==="
source /workspace/scripts/task_utils.sh

# 1. Load context
PATIENT_ID=$(cat /tmp/task_patient_id.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -z "$PATIENT_ID" ]; then
    echo "ERROR: Patient ID not found in /tmp/task_patient_id.txt"
    # Create failure result
    cat > /tmp/task_result.json << EOF
{
    "error": "Setup failed to provide patient ID",
    "phone_found": false,
    "success": false
}
EOF
    exit 0
fi

# 2. Check Database for Phone Number
# We look for a non-voided attribute of type 'Telephone Number' for this person
# We select the value and the creation timestamp
echo "Querying database for phone number..."

DB_RESULT=$(omrs_db_query "
SELECT pa.value, UNIX_TIMESTAMP(pa.date_created) 
FROM person_attribute pa 
JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id 
WHERE pa.person_id = '$PATIENT_ID' 
  AND pat.name = 'Telephone Number' 
  AND pa.voided = 0 
ORDER BY pa.date_created DESC LIMIT 1
")

PHONE_VALUE=""
PHONE_TIMESTAMP="0"
PHONE_FOUND="false"
CREATED_DURING_TASK="false"

if [ -n "$DB_RESULT" ]; then
    PHONE_FOUND="true"
    # Parse tab-separated result
    PHONE_VALUE=$(echo "$DB_RESULT" | cut -f1)
    PHONE_TIMESTAMP=$(echo "$DB_RESULT" | cut -f2)
    
    echo "Found phone number: '$PHONE_VALUE' created at $PHONE_TIMESTAMP"
    
    # Check timestamp against task start
    if [ "$PHONE_TIMESTAMP" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
        echo "Phone number was created during the task."
    else
        echo "WARNING: Phone number predates task start ($PHONE_TIMESTAMP <= $TASK_START)"
    fi
else
    echo "No phone number attribute found for patient $PATIENT_ID"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Export JSON
# We use python to safely generate JSON
python3 -c "
import json
import sys

result = {
    'patient_id': '$PATIENT_ID',
    'phone_found': $PHONE_FOUND,
    'phone_value': '$PHONE_VALUE',
    'created_during_task': $CREATED_DURING_TASK,
    'task_start_ts': $TASK_START,
    'phone_created_ts': $PHONE_TIMESTAMP
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="
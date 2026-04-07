#!/bin/bash
set -e
echo "=== Exporting Task Results ==="
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Read Task Context
TARGET_VISIT_UUID=$(cat /tmp/target_visit_uuid.txt 2>/dev/null || echo "")
PATIENT_UUID=$(cat /tmp/target_patient_uuid.txt 2>/dev/null || echo "")
INITIAL_VISIT_COUNT=$(cat /tmp/initial_visit_count.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -z "$TARGET_VISIT_UUID" ]; then
    echo "ERROR: Target visit UUID not found. Setup may have failed."
    # Create failure result
    echo '{"error": "Setup failed"}' > /tmp/task_result.json
    exit 0
fi

# 3. Verify Target Visit Status (Primary Metric)
# Check if voided and get void reason
VISIT_STATUS_JSON=$(omrs_db_query "SELECT JSON_OBJECT('voided', voided, 'void_reason', IFNULL(void_reason, ''), 'date_voided', IFNULL(UNIX_TIMESTAMP(date_voided), 0)) FROM visit WHERE uuid='$TARGET_VISIT_UUID';")
# Clean up mysql output if needed (sometimes it adds headers even with -N)
VISIT_STATUS_JSON=$(echo "$VISIT_STATUS_JSON" | grep "{" | head -1)

# 4. Verify Side Effects (Collateral Damage)
# Check if any OTHER visits for this patient were voided during the task
# We look for visits that are voided, belong to this patient, are NOT the target visit,
# and were voided AFTER task start.
COLLATERAL_COUNT=$(omrs_db_query "SELECT COUNT(*) FROM visit WHERE patient_id=(SELECT patient_id FROM patient WHERE uuid='$PATIENT_UUID') AND voided=1 AND uuid != '$TARGET_VISIT_UUID' AND UNIX_TIMESTAMP(date_voided) >= $TASK_START_TIME;")

# 5. Verify Active Count
CURRENT_ACTIVE_COUNT=$(omrs_db_query "SELECT COUNT(*) FROM visit WHERE patient_id=(SELECT patient_id FROM patient WHERE uuid='$PATIENT_UUID') AND voided=0;")

# 6. Construct Result JSON
# Using python to safely construct JSON
python3 -c "
import json
import os
import time

try:
    # Parse DB result
    status_raw = '''$VISIT_STATUS_JSON'''
    if not status_raw.strip():
        status = {'voided': 0, 'void_reason': '', 'date_voided': 0}
    else:
        status = json.loads(status_raw)

    result = {
        'target_visit_uuid': '$TARGET_VISIT_UUID',
        'is_voided': bool(status.get('voided', 0)),
        'void_reason': status.get('void_reason', ''),
        'void_timestamp': status.get('date_voided', 0),
        'task_start_timestamp': int('$TASK_START_TIME'),
        'initial_active_count': int('$INITIAL_VISIT_COUNT'),
        'final_active_count': int('$CURRENT_ACTIVE_COUNT'),
        'collateral_void_count': int('$COLLATERAL_COUNT'),
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error constructing result JSON: {e}')
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="
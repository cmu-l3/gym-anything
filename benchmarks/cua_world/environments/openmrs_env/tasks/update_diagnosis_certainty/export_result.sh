#!/bin/bash
echo "=== Exporting update_diagnosis_certainty results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# -----------------------------------------------------------------------------
# Query Database for Final State
# -----------------------------------------------------------------------------
PATIENT_UUID=$(cat /tmp/task_patient_uuid.txt 2>/dev/null || echo "")

# We query the encounter_diagnosis table to see the current state for this patient
# We look for Anemia (concept name like 'Anemia%')
# We retrieve: certainty, voided status, and timestamps
# We join with concept_name to ensure we get 'Anemia'

SQL_QUERY="
SELECT 
    ed.certainty, 
    ed.voided, 
    ed.date_changed, 
    ed.date_created, 
    cn.name as concept_name,
    e.uuid as encounter_uuid
FROM encounter_diagnosis ed
JOIN patient p ON ed.patient_id = p.patient_id
JOIN concept_name cn ON ed.diagnosis_coded_id = cn.concept_id
JOIN encounter e ON ed.encounter_id = e.encounter_id
WHERE p.uuid = '$PATIENT_UUID'
  AND cn.name LIKE 'Anemia%'
  AND cn.locale = 'en'
  AND cn.concept_name_type = 'FULLY_SPECIFIED'
ORDER BY ed.encounter_diagnosis_id DESC;
"

# Execute query and format as JSON
# Note: MariaDB output needs careful parsing or we can use python to execute and dump json
echo "Executing DB verification query..."

python3 -c "
import pymysql
import json
import os
import time

try:
    conn = pymysql.connect(
        host='127.0.0.1', 
        user='root',  # Try root first, or openmrs user from env
        password='password', # Env default
        database='openmrs',
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor
    )
except:
    # Fallback to standard openmrs docker creds if root fails
    # This assumes the script runs inside container or has port access. 
    # Since this is 'export_result.sh' running in the env, we can use the 'omrs_db_query' helper 
    # but for structured JSON output, python is cleaner.
    # Let's rely on the omrs_db_query helper from task_utils which executes inside the docker container
    pass

# We'll use the docker exec method via subprocess if direct connection fails
# But simply, let's use the omrs_db_query wrapper and parse text, 
# or better, use docker exec directly with json output if possible. 
# Simplest robust way given the environment: Use the existing omrs_db_query and parse CSV/TSV.
"

# Use the helper function to get raw TSV
RAW_RESULT=$(omrs_db_query "$SQL_QUERY")

# Convert TSV to JSON using Python
JSON_RESULT=$(python3 -c "
import sys, json, csv, io
raw = '''$RAW_RESULT'''
data = []
# Skip empty lines
lines = [l for l in raw.split('\n') if l.strip()]
if lines:
    # Manually map columns since omrs_db_query -N removes headers usually
    # Columns from SQL: certainty, voided, date_changed, date_created, concept_name, encounter_uuid
    for line in lines:
        parts = line.split('\t')
        if len(parts) >= 6:
            data.append({
                'certainty': parts[0],
                'voided': parts[1] == '1',
                'date_changed': parts[2],
                'date_created': parts[3],
                'concept_name': parts[4],
                'encounter_uuid': parts[5]
            })
print(json.dumps(data))
")

# Check if browser is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "db_diagnoses": $JSON_RESULT
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json
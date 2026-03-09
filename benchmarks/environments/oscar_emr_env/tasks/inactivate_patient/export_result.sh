#!/bin/bash
# Export script for Inactivate Patient task
# Exports database state to JSON for verifier

echo "=== Exporting Inactivate Patient Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Data
DEMO_NO="10050"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Query patient data
# We fetch: status, lastUpdateDate (as unix timestamp), and some integrity fields
QUERY="SELECT patient_status, 
              UNIX_TIMESTAMP(lastUpdateDate), 
              last_name, 
              first_name, 
              date_of_birth,
              demographic_no
       FROM demographic 
       WHERE demographic_no='$DEMO_NO'"

DATA=$(oscar_query "$QUERY")

# 3. Process Data into JSON variables
PATIENT_FOUND="false"
STATUS=""
UPDATE_TIME="0"
INTEGRITY_NAME=""
INTEGRITY_DOB=""

if [ -n "$DATA" ]; then
    PATIENT_FOUND="true"
    STATUS=$(echo "$DATA" | cut -f1)
    UPDATE_TIME=$(echo "$DATA" | cut -f2)
    LNAME=$(echo "$DATA" | cut -f3)
    FNAME=$(echo "$DATA" | cut -f4)
    DOB=$(echo "$DATA" | cut -f5)
    
    INTEGRITY_NAME="$FNAME $LNAME"
    INTEGRITY_DOB="$DOB"
fi

# 4. Check application state
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $CURRENT_TIME,
    "patient_found": $PATIENT_FOUND,
    "patient_id": "$DEMO_NO",
    "final_status": "$STATUS",
    "last_update_timestamp": ${UPDATE_TIME:-0},
    "integrity_name": "$INTEGRITY_NAME",
    "integrity_dob": "$INTEGRITY_DOB",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="
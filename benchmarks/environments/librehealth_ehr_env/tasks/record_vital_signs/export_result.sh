#!/bin/bash
set -e
echo "=== Exporting Record Vital Signs Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_VITALS_COUNT=$(cat /tmp/initial_vitals_count.txt 2>/dev/null || echo "0")
TARGET_PID=$(cat /tmp/target_patient_pid.txt 2>/dev/null || echo "")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
VITALS_FOUND="false"
VITALS_DATA="{}"
NEW_RECORD_CREATED="false"
CURRENT_VITALS_COUNT="0"
TIMESTAMP_VALID="false"

# Query current total count
CURRENT_VITALS_COUNT=$(librehealth_query "SELECT COUNT(*) FROM form_vitals" 2>/dev/null || echo "0")

if [ "$CURRENT_VITALS_COUNT" -gt "$INITIAL_VITALS_COUNT" ]; then
    NEW_RECORD_CREATED="true"
fi

# Query specific patient vitals
# We look for the most recent vitals form for this patient
if [ -n "$TARGET_PID" ]; then
    # Query: Get the most recent vitals form for this PID
    # Note: Joins form_vitals (fv) with forms (f) on id=form_id
    QUERY="SELECT fv.bps, fv.bpd, fv.pulse, fv.temperature, fv.respiration, fv.oxygen_saturation, fv.height, fv.weight, UNIX_TIMESTAMP(fv.date) 
           FROM form_vitals fv 
           JOIN forms f ON f.form_id = fv.id 
           WHERE f.pid = '${TARGET_PID}' AND f.formdir = 'vitals' 
           ORDER BY fv.id DESC LIMIT 1"
    
    RESULT_ROW=$(librehealth_query "$QUERY")
    
    if [ -n "$RESULT_ROW" ]; then
        VITALS_FOUND="true"
        
        # Parse result row (tab separated)
        # Expected: bps bpd pulse temp resp o2 height weight timestamp
        BPS=$(echo "$RESULT_ROW" | awk '{print $1}')
        BPD=$(echo "$RESULT_ROW" | awk '{print $2}')
        PULSE=$(echo "$RESULT_ROW" | awk '{print $3}')
        TEMP=$(echo "$RESULT_ROW" | awk '{print $4}')
        RESP=$(echo "$RESULT_ROW" | awk '{print $5}')
        O2=$(echo "$RESULT_ROW" | awk '{print $6}')
        HEIGHT=$(echo "$RESULT_ROW" | awk '{print $7}')
        WEIGHT=$(echo "$RESULT_ROW" | awk '{print $8}')
        RECORD_TIME=$(echo "$RESULT_ROW" | awk '{print $9}')
        
        # Check timestamp validity (allow 60s skew before start, must be before end)
        if [ "$RECORD_TIME" -ge $((TASK_START - 60)) ] && [ "$RECORD_TIME" -le $((TASK_END + 60)) ]; then
            TIMESTAMP_VALID="true"
        fi
        
        # Construct JSON object for values
        VITALS_DATA=$(cat <<EOF
{
    "bps": "$BPS",
    "bpd": "$BPD",
    "pulse": "$PULSE",
    "temperature": "$TEMP",
    "respiration": "$RESP",
    "oxygen_saturation": "$O2",
    "height": "$HEIGHT",
    "weight": "$WEIGHT",
    "timestamp": $RECORD_TIME
}
EOF
)
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_pid": "$TARGET_PID",
    "vitals_found": $VITALS_FOUND,
    "new_record_created": $NEW_RECORD_CREATED,
    "timestamp_valid": $TIMESTAMP_VALID,
    "vitals_data": $VITALS_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
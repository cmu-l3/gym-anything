#!/bin/bash
# Export script for Assign Patient Price Level Task

echo "=== Exporting Assign Price Level Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot first
sleep 1
take_screenshot /tmp/task_final_screenshot.png
echo "Final screenshot saved"

# Target patient
PATIENT_PID=5

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_PRICE_LEVEL=$(cat /tmp/initial_price_level 2>/dev/null || echo "Standard")
INITIAL_MOD_TIME=$(cat /tmp/initial_mod_time 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"
echo "Initial price level: $INITIAL_PRICE_LEVEL"

# Query current patient data
echo ""
echo "=== Querying patient data ==="
PATIENT_DATA=$(openemr_query "SELECT pid, fname, lname, DOB, pricelevel, UNIX_TIMESTAMP(date) as mod_time FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Patient data: $PATIENT_DATA"

# Parse patient data
PATIENT_FOUND="false"
CURRENT_FNAME=""
CURRENT_LNAME=""
CURRENT_DOB=""
CURRENT_PRICELEVEL=""
CURRENT_MOD_TIME="0"

if [ -n "$PATIENT_DATA" ]; then
    PATIENT_FOUND="true"
    CURRENT_FNAME=$(echo "$PATIENT_DATA" | cut -f2)
    CURRENT_LNAME=$(echo "$PATIENT_DATA" | cut -f3)
    CURRENT_DOB=$(echo "$PATIENT_DATA" | cut -f4)
    CURRENT_PRICELEVEL=$(echo "$PATIENT_DATA" | cut -f5)
    CURRENT_MOD_TIME=$(echo "$PATIENT_DATA" | cut -f6)
    
    echo ""
    echo "Parsed patient data:"
    echo "  Name: $CURRENT_FNAME $CURRENT_LNAME"
    echo "  DOB: $CURRENT_DOB"
    echo "  Price Level: $CURRENT_PRICELEVEL"
    echo "  Modification Time: $CURRENT_MOD_TIME"
fi

# Check if price level was changed
PRICE_LEVEL_CHANGED="false"
if [ "$CURRENT_PRICELEVEL" != "$INITIAL_PRICE_LEVEL" ]; then
    PRICE_LEVEL_CHANGED="true"
    echo "Price level was changed from '$INITIAL_PRICE_LEVEL' to '$CURRENT_PRICELEVEL'"
else
    echo "Price level unchanged: '$CURRENT_PRICELEVEL'"
fi

# Check if correct price level was set
CORRECT_PRICE_LEVEL="false"
# Handle various possible formats (with/without spaces, different cases)
NORMALIZED_PRICELEVEL=$(echo "$CURRENT_PRICELEVEL" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
if [ "$NORMALIZED_PRICELEVEL" = "sliding1" ] || [ "$CURRENT_PRICELEVEL" = "Sliding 1" ] || [ "$CURRENT_PRICELEVEL" = "Sliding1" ]; then
    CORRECT_PRICE_LEVEL="true"
    echo "Correct price level 'Sliding 1' was set"
fi

# Check if record was modified during task
RECORD_MODIFIED_DURING_TASK="false"
if [ "$CURRENT_MOD_TIME" -gt "$TASK_START" ] 2>/dev/null; then
    RECORD_MODIFIED_DURING_TASK="true"
    echo "Record was modified during task (mod_time=$CURRENT_MOD_TIME > start=$TASK_START)"
else
    echo "Record modification time not updated or before task start"
fi

# Also check if modification time is greater than initial
RECORD_UPDATED="false"
if [ "$CURRENT_MOD_TIME" -gt "$INITIAL_MOD_TIME" ] 2>/dev/null; then
    RECORD_UPDATED="true"
    echo "Record was updated (mod_time changed: $INITIAL_MOD_TIME -> $CURRENT_MOD_TIME)"
fi

# Debug: Show all patients with non-standard price levels
echo ""
echo "=== DEBUG: Patients with non-standard price levels ==="
openemr_query "SELECT pid, fname, lname, pricelevel FROM patient_data WHERE pricelevel != 'Standard' AND pricelevel != '' AND pricelevel IS NOT NULL LIMIT 10" 2>/dev/null || echo "None found"

# Escape special characters for JSON
CURRENT_PRICELEVEL_ESCAPED=$(echo "$CURRENT_PRICELEVEL" | sed 's/"/\\"/g')
INITIAL_PRICE_LEVEL_ESCAPED=$(echo "$INITIAL_PRICE_LEVEL" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/price_level_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "patient_found": $PATIENT_FOUND,
    "patient": {
        "fname": "$CURRENT_FNAME",
        "lname": "$CURRENT_LNAME",
        "dob": "$CURRENT_DOB"
    },
    "price_level": {
        "initial": "$INITIAL_PRICE_LEVEL_ESCAPED",
        "current": "$CURRENT_PRICELEVEL_ESCAPED",
        "expected": "Sliding 1"
    },
    "validation": {
        "price_level_changed": $PRICE_LEVEL_CHANGED,
        "correct_price_level": $CORRECT_PRICE_LEVEL,
        "record_modified_during_task": $RECORD_MODIFIED_DURING_TASK,
        "record_updated": $RECORD_UPDATED
    },
    "timestamps": {
        "task_start": $TASK_START,
        "task_end": $TASK_END,
        "initial_mod_time": $INITIAL_MOD_TIME,
        "current_mod_time": $CURRENT_MOD_TIME
    },
    "screenshots": {
        "initial": "/tmp/task_initial_screenshot.png",
        "final": "/tmp/task_final_screenshot.png"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/price_level_result.json 2>/dev/null || sudo rm -f /tmp/price_level_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/price_level_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/price_level_result.json
chmod 666 /tmp/price_level_result.json 2>/dev/null || sudo chmod 666 /tmp/price_level_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/price_level_result.json"
cat /tmp/price_level_result.json

echo ""
echo "=== Export Complete ==="
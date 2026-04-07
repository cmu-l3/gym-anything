#!/bin/bash
# Export script for Document Family History task
# Queries database and saves results for verifier

echo "=== Exporting Document Family History Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png
echo "Final screenshot saved to /tmp/task_final_state.png"

# Target patient
PATIENT_PID=4

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Load initial state
INITIAL_HISTORY_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_family_history_state.json')).get('initial_history_count', 0))" 2>/dev/null || echo "0")
INITIAL_LISTS_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_family_history_state.json')).get('initial_lists_count', 0))" 2>/dev/null || echo "0")
INITIAL_HISTORY_DATA=$(python3 -c "import json; print(json.load(open('/tmp/initial_family_history_state.json')).get('initial_history_data', ''))" 2>/dev/null || echo "")

echo "Task timing: start=$TASK_START, end=$TASK_END"
echo "Initial state: history_count=$INITIAL_HISTORY_COUNT, lists_count=$INITIAL_LISTS_COUNT"

# Query current history_data for this patient
echo ""
echo "=== Querying history_data table for patient PID=$PATIENT_PID ==="
HISTORY_DATA=$(openemr_query "SELECT id, relatives_diabetes, relatives_heart_problems, relatives_cancer, relatives_high_blood_pressure, relatives_stroke, date FROM history_data WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
echo "History data: $HISTORY_DATA"

# Get current counts
CURRENT_HISTORY_COUNT=$(openemr_query "SELECT COUNT(*) FROM history_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_LISTS_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='family_history'" 2>/dev/null || echo "0")

echo "Current counts: history=$CURRENT_HISTORY_COUNT, lists=$CURRENT_LISTS_COUNT"

# Parse history_data fields
HISTORY_ID=""
RELATIVES_DIABETES=""
RELATIVES_HEART=""
RELATIVES_CANCER=""
RELATIVES_HBP=""
RELATIVES_STROKE=""
HISTORY_DATE=""

if [ -n "$HISTORY_DATA" ]; then
    HISTORY_ID=$(echo "$HISTORY_DATA" | cut -f1)
    RELATIVES_DIABETES=$(echo "$HISTORY_DATA" | cut -f2)
    RELATIVES_HEART=$(echo "$HISTORY_DATA" | cut -f3)
    RELATIVES_CANCER=$(echo "$HISTORY_DATA" | cut -f4)
    RELATIVES_HBP=$(echo "$HISTORY_DATA" | cut -f5)
    RELATIVES_STROKE=$(echo "$HISTORY_DATA" | cut -f6)
    HISTORY_DATE=$(echo "$HISTORY_DATA" | cut -f7)
    
    echo ""
    echo "Parsed history data:"
    echo "  ID: $HISTORY_ID"
    echo "  Diabetes: $RELATIVES_DIABETES"
    echo "  Heart Problems: $RELATIVES_HEART"
    echo "  Cancer: $RELATIVES_CANCER"
    echo "  High BP: $RELATIVES_HBP"
    echo "  Stroke: $RELATIVES_STROKE"
    echo "  Date: $HISTORY_DATE"
fi

# Also query lists table for family_history type entries
echo ""
echo "=== Querying lists table for family_history entries ==="
LISTS_DATA=$(openemr_query "SELECT id, title, diagnosis, comments, date FROM lists WHERE pid=$PATIENT_PID AND type='family_history' ORDER BY id DESC LIMIT 10" 2>/dev/null)
echo "Lists data: $LISTS_DATA"

# Check if data changed from initial state
DATA_CHANGED="false"
CURRENT_DATA_STRING="${RELATIVES_DIABETES}|${RELATIVES_HEART}|${RELATIVES_CANCER}"
if [ "$CURRENT_DATA_STRING" != "$INITIAL_HISTORY_DATA" ] || [ "$CURRENT_HISTORY_COUNT" -gt "$INITIAL_HISTORY_COUNT" ] || [ "$CURRENT_LISTS_COUNT" -gt "$INITIAL_LISTS_COUNT" ]; then
    DATA_CHANGED="true"
    echo "Family history data has changed since task start"
else
    echo "WARNING: No change detected in family history data"
fi

# Check for specific keywords in the fields
DIABETES_DOCUMENTED="false"
HEART_DOCUMENTED="false"
CANCER_DOCUMENTED="false"

# Check diabetes field
if [ -n "$RELATIVES_DIABETES" ]; then
    DIABETES_LOWER=$(echo "$RELATIVES_DIABETES" | tr '[:upper:]' '[:lower:]')
    if echo "$DIABETES_LOWER" | grep -qE "(mother|maternal|diabetes|dm|type.?2)"; then
        DIABETES_DOCUMENTED="true"
    elif [ -n "$RELATIVES_DIABETES" ] && [ "$RELATIVES_DIABETES" != "NULL" ]; then
        # Any non-empty content counts
        DIABETES_DOCUMENTED="true"
    fi
fi

# Check heart field
if [ -n "$RELATIVES_HEART" ]; then
    HEART_LOWER=$(echo "$RELATIVES_HEART" | tr '[:upper:]' '[:lower:]')
    if echo "$HEART_LOWER" | grep -qE "(father|paternal|heart|mi|myocardial|infarction|attack|cardiac)"; then
        HEART_DOCUMENTED="true"
    elif [ -n "$RELATIVES_HEART" ] && [ "$RELATIVES_HEART" != "NULL" ]; then
        HEART_DOCUMENTED="true"
    fi
fi

# Check cancer field
if [ -n "$RELATIVES_CANCER" ]; then
    CANCER_LOWER=$(echo "$RELATIVES_CANCER" | tr '[:upper:]' '[:lower:]')
    if echo "$CANCER_LOWER" | grep -qE "(grandmother|grandma|maternal|breast|cancer|carcinoma)"; then
        CANCER_DOCUMENTED="true"
    elif [ -n "$RELATIVES_CANCER" ] && [ "$RELATIVES_CANCER" != "NULL" ]; then
        CANCER_DOCUMENTED="true"
    fi
fi

# Also check lists table entries
if [ "$CURRENT_LISTS_COUNT" -gt "$INITIAL_LISTS_COUNT" ]; then
    LISTS_LOWER=$(echo "$LISTS_DATA" | tr '[:upper:]' '[:lower:]')
    if echo "$LISTS_LOWER" | grep -qE "diabetes" && [ "$DIABETES_DOCUMENTED" = "false" ]; then
        DIABETES_DOCUMENTED="true"
    fi
    if echo "$LISTS_LOWER" | grep -qE "(heart|mi|myocardial|cardiac)" && [ "$HEART_DOCUMENTED" = "false" ]; then
        HEART_DOCUMENTED="true"
    fi
    if echo "$LISTS_LOWER" | grep -qE "cancer" && [ "$CANCER_DOCUMENTED" = "false" ]; then
        CANCER_DOCUMENTED="true"
    fi
fi

echo ""
echo "Documentation status:"
echo "  Diabetes documented: $DIABETES_DOCUMENTED"
echo "  Heart disease documented: $HEART_DOCUMENTED"
echo "  Cancer documented: $CANCER_DOCUMENTED"

# Escape special characters for JSON
RELATIVES_DIABETES_ESC=$(echo "$RELATIVES_DIABETES" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
RELATIVES_HEART_ESC=$(echo "$RELATIVES_HEART" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
RELATIVES_CANCER_ESC=$(echo "$RELATIVES_CANCER" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
LISTS_DATA_ESC=$(echo "$LISTS_DATA" | sed 's/"/\\"/g' | tr '\n' ';' | head -c 1000)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/family_history_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "initial_history_count": ${INITIAL_HISTORY_COUNT:-0},
    "current_history_count": ${CURRENT_HISTORY_COUNT:-0},
    "initial_lists_count": ${INITIAL_LISTS_COUNT:-0},
    "current_lists_count": ${CURRENT_LISTS_COUNT:-0},
    "data_changed": $DATA_CHANGED,
    "history_data": {
        "id": "$HISTORY_ID",
        "relatives_diabetes": "$RELATIVES_DIABETES_ESC",
        "relatives_heart_problems": "$RELATIVES_HEART_ESC",
        "relatives_cancer": "$RELATIVES_CANCER_ESC",
        "date": "$HISTORY_DATE"
    },
    "lists_entries": "$LISTS_DATA_ESC",
    "documentation_status": {
        "diabetes_documented": $DIABETES_DOCUMENTED,
        "heart_documented": $HEART_DOCUMENTED,
        "cancer_documented": $CANCER_DOCUMENTED
    },
    "screenshots": {
        "initial": "/tmp/task_initial_state.png",
        "final": "/tmp/task_final_state.png"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/family_history_result.json 2>/dev/null || sudo rm -f /tmp/family_history_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/family_history_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/family_history_result.json
chmod 666 /tmp/family_history_result.json 2>/dev/null || sudo chmod 666 /tmp/family_history_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/family_history_result.json"
cat /tmp/family_history_result.json

echo ""
echo "=== Export Complete ==="
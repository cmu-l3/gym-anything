#!/bin/bash
# Export script for Record Social History Task

echo "=== Exporting Record Social History Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot first
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Target patient
PATIENT_PID=3

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Query current history_data for this patient
echo ""
echo "=== Querying current social history for patient PID=$PATIENT_PID ==="

# Get all history fields
CURRENT_HISTORY=$(openemr_query "SELECT id, date, tobacco, coffee, alcohol, sleep_patterns, exercise_patterns, hazardous_activities, recreational_drugs, occupation, counseling FROM history_data WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")

echo "Current history record:"
echo "$CURRENT_HISTORY"

# Also check for usertext fields which may contain additional data
HISTORY_USERTEXT=$(openemr_query "SELECT usertext11, usertext12, usertext13, usertext14, usertext15 FROM history_data WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")

echo ""
echo "Additional usertext fields:"
echo "$HISTORY_USERTEXT"

# Parse the history data
HISTORY_ID=""
HISTORY_DATE=""
TOBACCO=""
COFFEE=""
ALCOHOL=""
SLEEP=""
EXERCISE=""
HAZARDOUS=""
DRUGS=""
OCCUPATION=""
COUNSELING=""

if [ -n "$CURRENT_HISTORY" ]; then
    HISTORY_ID=$(echo "$CURRENT_HISTORY" | cut -f1)
    HISTORY_DATE=$(echo "$CURRENT_HISTORY" | cut -f2)
    TOBACCO=$(echo "$CURRENT_HISTORY" | cut -f3)
    COFFEE=$(echo "$CURRENT_HISTORY" | cut -f4)
    ALCOHOL=$(echo "$CURRENT_HISTORY" | cut -f5)
    SLEEP=$(echo "$CURRENT_HISTORY" | cut -f6)
    EXERCISE=$(echo "$CURRENT_HISTORY" | cut -f7)
    HAZARDOUS=$(echo "$CURRENT_HISTORY" | cut -f8)
    DRUGS=$(echo "$CURRENT_HISTORY" | cut -f9)
    OCCUPATION=$(echo "$CURRENT_HISTORY" | cut -f10)
    COUNSELING=$(echo "$CURRENT_HISTORY" | cut -f11)
fi

# Check if tobacco field contains relevant keywords
TOBACCO_LOWER=$(echo "$TOBACCO" | tr '[:upper:]' '[:lower:]')
SMOKING_STATUS_VALID="false"
if echo "$TOBACCO_LOWER" | grep -qiE "(former|quit|ex-|past|stopped|no longer)"; then
    SMOKING_STATUS_VALID="true"
    echo "Smoking status indicates former smoker: VALID"
else
    echo "Smoking status does not indicate former smoker"
fi

# Check for quit date (2018-06-15 or variations)
QUIT_DATE_VALID="false"
if echo "$TOBACCO $COUNSELING" | grep -qE "(2018|06.?15|June.?15)"; then
    QUIT_DATE_VALID="true"
    echo "Quit date found: VALID"
else
    echo "Quit date not found in expected format"
fi

# Check alcohol field
ALCOHOL_LOWER=$(echo "$ALCOHOL" | tr '[:upper:]' '[:lower:]')
ALCOHOL_VALID="false"
if echo "$ALCOHOL_LOWER" | grep -qiE "(social|moderate|occasional|2-3|drinks)"; then
    ALCOHOL_VALID="true"
    echo "Alcohol use documented appropriately: VALID"
fi

# Check drugs field
DRUGS_LOWER=$(echo "$DRUGS" | tr '[:upper:]' '[:lower:]')
DRUGS_VALID="false"
if echo "$DRUGS_LOWER" | grep -qiE "(none|no|denies|negative|never)"; then
    DRUGS_VALID="true"
    echo "Drug use denial documented: VALID"
elif [ -z "$DRUGS" ] || [ "$DRUGS" = "NULL" ]; then
    # Empty might also indicate none
    DRUGS_VALID="true"
    echo "Drug use field empty (acceptable for 'none')"
fi

# Check occupation field
OCCUPATION_LOWER=$(echo "$OCCUPATION" | tr '[:upper:]' '[:lower:]')
OCCUPATION_VALID="false"
if echo "$OCCUPATION_LOWER" | grep -qiE "(software|developer|engineer|programmer|tech)"; then
    OCCUPATION_VALID="true"
    echo "Occupation documented correctly: VALID"
fi

# Check exercise field
EXERCISE_LOWER=$(echo "$EXERCISE" | tr '[:upper:]' '[:lower:]')
EXERCISE_VALID="false"
if echo "$EXERCISE_LOWER" | grep -qiE "(moderate|walk|30|daily|regular)"; then
    EXERCISE_VALID="true"
    echo "Exercise documented: VALID"
fi

# Check if history was modified during task
HISTORY_MODIFIED="false"
if [ -n "$HISTORY_DATE" ]; then
    # Try to parse the date and compare
    HISTORY_EPOCH=$(date -d "$HISTORY_DATE" +%s 2>/dev/null || echo "0")
    if [ "$HISTORY_EPOCH" -ge "$TASK_START" ]; then
        HISTORY_MODIFIED="true"
        echo "History record was modified during task"
    fi
fi

# Also check by comparing with initial state
INITIAL_TOBACCO=$(python3 -c "import json; d=json.load(open('/tmp/initial_history_state.json')); h=d.get('initial_history',{}); print(h.get('tobacco','') if h else '')" 2>/dev/null || echo "")
if [ "$TOBACCO" != "$INITIAL_TOBACCO" ] && [ -n "$TOBACCO" ]; then
    HISTORY_MODIFIED="true"
    echo "Tobacco field changed from initial state"
fi

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\t/ /g' | tr '\n' ' ' | tr '\r' ' '
}

TOBACCO_ESC=$(escape_json "$TOBACCO")
ALCOHOL_ESC=$(escape_json "$ALCOHOL")
DRUGS_ESC=$(escape_json "$DRUGS")
OCCUPATION_ESC=$(escape_json "$OCCUPATION")
EXERCISE_ESC=$(escape_json "$EXERCISE")
COUNSELING_ESC=$(escape_json "$COUNSELING")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/social_history_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "history_record": {
        "id": "$HISTORY_ID",
        "date": "$HISTORY_DATE",
        "tobacco": "$TOBACCO_ESC",
        "alcohol": "$ALCOHOL_ESC",
        "recreational_drugs": "$DRUGS_ESC",
        "occupation": "$OCCUPATION_ESC",
        "exercise": "$EXERCISE_ESC",
        "counseling": "$COUNSELING_ESC"
    },
    "validation": {
        "smoking_status_valid": $SMOKING_STATUS_VALID,
        "quit_date_valid": $QUIT_DATE_VALID,
        "alcohol_valid": $ALCOHOL_VALID,
        "drugs_valid": $DRUGS_VALID,
        "occupation_valid": $OCCUPATION_VALID,
        "exercise_valid": $EXERCISE_VALID,
        "history_modified_during_task": $HISTORY_MODIFIED
    },
    "screenshot_path": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/social_history_result.json 2>/dev/null || sudo rm -f /tmp/social_history_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/social_history_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/social_history_result.json
chmod 666 /tmp/social_history_result.json 2>/dev/null || sudo chmod 666 /tmp/social_history_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Result JSON ==="
cat /tmp/social_history_result.json

echo ""
echo "=== Export Complete ==="
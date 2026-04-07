#!/bin/bash
# Export script for Resolve Medical Problem task

echo "=== Exporting Resolve Medical Problem Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Target patient
PATIENT_PID=1

# Get stored values from setup
TARGET_PROBLEM_ID=$(cat /tmp/target_problem_id.txt 2>/dev/null || echo "")
ORIGINAL_BEGDATE=$(cat /tmp/original_begdate.txt 2>/dev/null || echo "")
ORIGINAL_TITLE=$(cat /tmp/original_title.txt 2>/dev/null || echo "")
INITIAL_BRONCHITIS_COUNT=$(cat /tmp/initial_bronchitis_count.txt 2>/dev/null || echo "1")

echo "Task start: $TASK_START"
echo "Task end: $TASK_END"
echo "Target problem ID: $TARGET_PROBLEM_ID"
echo "Original begin date: $ORIGINAL_BEGDATE"
echo "Initial bronchitis count: $INITIAL_BRONCHITIS_COUNT"

# Query for ALL bronchitis problems for this patient
echo ""
echo "=== Querying bronchitis problems for patient PID=$PATIENT_PID ==="
ALL_BRONCHITIS=$(openemr_query "SELECT id, title, begdate, enddate, outcome FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%ronchitis%' OR title LIKE '%RONCHITIS%') ORDER BY id DESC" 2>/dev/null)
echo "All bronchitis entries:"
echo "$ALL_BRONCHITIS"

# Get current count of bronchitis problems
CURRENT_BRONCHITIS_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%ronchitis%' OR title LIKE '%RONCHITIS%')" 2>/dev/null || echo "0")
echo "Current bronchitis problem count: $CURRENT_BRONCHITIS_COUNT"

# Query the specific target problem
echo ""
echo "=== Querying target problem ID=$TARGET_PROBLEM_ID ==="
if [ -n "$TARGET_PROBLEM_ID" ]; then
    TARGET_PROBLEM=$(openemr_query "SELECT id, pid, type, title, begdate, enddate, outcome, modifydate FROM lists WHERE id=$TARGET_PROBLEM_ID" 2>/dev/null)
    echo "Target problem data: $TARGET_PROBLEM"
fi

# Parse target problem data
PROBLEM_FOUND="false"
CURRENT_ENDDATE=""
CURRENT_BEGDATE=""
CURRENT_TITLE=""
MODIFY_DATE=""

if [ -n "$TARGET_PROBLEM" ]; then
    PROBLEM_FOUND="true"
    PROBLEM_ID=$(echo "$TARGET_PROBLEM" | cut -f1)
    PROBLEM_PID=$(echo "$TARGET_PROBLEM" | cut -f2)
    PROBLEM_TYPE=$(echo "$TARGET_PROBLEM" | cut -f3)
    CURRENT_TITLE=$(echo "$TARGET_PROBLEM" | cut -f4)
    CURRENT_BEGDATE=$(echo "$TARGET_PROBLEM" | cut -f5)
    CURRENT_ENDDATE=$(echo "$TARGET_PROBLEM" | cut -f6)
    CURRENT_OUTCOME=$(echo "$TARGET_PROBLEM" | cut -f7)
    MODIFY_DATE=$(echo "$TARGET_PROBLEM" | cut -f8)
    
    echo ""
    echo "Parsed problem data:"
    echo "  ID: $PROBLEM_ID"
    echo "  Title: $CURRENT_TITLE"
    echo "  Begin Date: $CURRENT_BEGDATE"
    echo "  End Date: $CURRENT_ENDDATE"
    echo "  Outcome: $CURRENT_OUTCOME"
    echo "  Modified: $MODIFY_DATE"
fi

# Check if enddate is now populated
ENDDATE_POPULATED="false"
if [ -n "$CURRENT_ENDDATE" ] && [ "$CURRENT_ENDDATE" != "NULL" ] && [ "$CURRENT_ENDDATE" != "0000-00-00" ]; then
    ENDDATE_POPULATED="true"
    echo "End date IS populated: $CURRENT_ENDDATE"
else
    echo "End date is NOT populated (still NULL or empty)"
fi

# Check if begin date was preserved
BEGDATE_PRESERVED="false"
if [ "$CURRENT_BEGDATE" = "$ORIGINAL_BEGDATE" ]; then
    BEGDATE_PRESERVED="true"
    echo "Begin date preserved: $CURRENT_BEGDATE"
else
    echo "WARNING: Begin date changed from '$ORIGINAL_BEGDATE' to '$CURRENT_BEGDATE'"
fi

# Check if title was preserved
TITLE_PRESERVED="false"
CURRENT_TITLE_LOWER=$(echo "$CURRENT_TITLE" | tr '[:upper:]' '[:lower:]')
ORIGINAL_TITLE_LOWER=$(echo "$ORIGINAL_TITLE" | tr '[:upper:]' '[:lower:]')
if [ "$CURRENT_TITLE_LOWER" = "$ORIGINAL_TITLE_LOWER" ]; then
    TITLE_PRESERVED="true"
fi

# Check if a duplicate was created
DUPLICATE_CREATED="false"
if [ "$CURRENT_BRONCHITIS_COUNT" -gt "$INITIAL_BRONCHITIS_COUNT" ]; then
    DUPLICATE_CREATED="true"
    echo "WARNING: Duplicate entry may have been created (count: $INITIAL_BRONCHITIS_COUNT -> $CURRENT_BRONCHITIS_COUNT)"
fi

# Validate enddate is reasonable (should be today or yesterday, within 24 hours)
ENDDATE_VALID="false"
if [ "$ENDDATE_POPULATED" = "true" ]; then
    TODAY=$(date +%Y-%m-%d)
    YESTERDAY=$(date -d "-1 day" +%Y-%m-%d)
    if [ "$CURRENT_ENDDATE" = "$TODAY" ] || [ "$CURRENT_ENDDATE" = "$YESTERDAY" ]; then
        ENDDATE_VALID="true"
        echo "End date is valid (today or yesterday)"
    else
        echo "End date '$CURRENT_ENDDATE' is outside expected range (today: $TODAY)"
    fi
    
    # Also check enddate is not before begdate
    if [ -n "$CURRENT_BEGDATE" ]; then
        BEGDATE_EPOCH=$(date -d "$CURRENT_BEGDATE" +%s 2>/dev/null || echo "0")
        ENDDATE_EPOCH=$(date -d "$CURRENT_ENDDATE" +%s 2>/dev/null || echo "0")
        if [ "$ENDDATE_EPOCH" -lt "$BEGDATE_EPOCH" ]; then
            ENDDATE_VALID="false"
            echo "ERROR: End date is before begin date!"
        fi
    fi
fi

# Escape special characters for JSON
CURRENT_TITLE_ESCAPED=$(echo "$CURRENT_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ')
ORIGINAL_TITLE_ESCAPED=$(echo "$ORIGINAL_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/resolve_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "patient_pid": $PATIENT_PID,
    "target_problem_id": "$TARGET_PROBLEM_ID",
    "problem_found": $PROBLEM_FOUND,
    "problem": {
        "id": "$PROBLEM_ID",
        "title": "$CURRENT_TITLE_ESCAPED",
        "begdate": "$CURRENT_BEGDATE",
        "enddate": "$CURRENT_ENDDATE",
        "outcome": "$CURRENT_OUTCOME"
    },
    "original_data": {
        "begdate": "$ORIGINAL_BEGDATE",
        "title": "$ORIGINAL_TITLE_ESCAPED"
    },
    "validation": {
        "enddate_populated": $ENDDATE_POPULATED,
        "enddate_valid": $ENDDATE_VALID,
        "begdate_preserved": $BEGDATE_PRESERVED,
        "title_preserved": $TITLE_PRESERVED,
        "duplicate_created": $DUPLICATE_CREATED
    },
    "counts": {
        "initial_bronchitis_count": $INITIAL_BRONCHITIS_COUNT,
        "current_bronchitis_count": $CURRENT_BRONCHITIS_COUNT
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location
rm -f /tmp/resolve_problem_result.json 2>/dev/null || sudo rm -f /tmp/resolve_problem_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/resolve_problem_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/resolve_problem_result.json
chmod 666 /tmp/resolve_problem_result.json 2>/dev/null || sudo chmod 666 /tmp/resolve_problem_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/resolve_problem_result.json"
cat /tmp/resolve_problem_result.json
echo ""
echo "=== Export Complete ==="
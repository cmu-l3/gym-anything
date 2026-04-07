#!/bin/bash
echo "=== Exporting Configure Activity Dependencies Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time.txt

# Capture final state
take_screenshot /tmp/task_final.png ga

# Query MariaDB for the actual configuration state
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='ERGO101'" | tr -d '\r\n')

if [ -z "$COURSE_ID" ]; then
    echo "Error: Course ERGO101 not found."
    COURSE_ID="0"
    PAGE_ID="0"
    PAGE_COMPLETION="0"
    PAGE_COMPLETIONVIEW="0"
    CHOICE_ID="0"
    CHOICE_AVAILABILITY=""
else
    # Query Guide module state
    PAGE_INFO=$(moodle_query "SELECT id, completion, completionview FROM mdl_course_modules WHERE course=$COURSE_ID AND module=(SELECT id FROM mdl_modules WHERE name='page') AND instance=(SELECT id FROM mdl_page WHERE name='Ergonomics Guide') LIMIT 1")
    PAGE_ID=$(echo "$PAGE_INFO" | cut -f1 | tr -d '\r\n')
    PAGE_COMPLETION=$(echo "$PAGE_INFO" | cut -f2 | tr -d '\r\n')
    PAGE_COMPLETIONVIEW=$(echo "$PAGE_INFO" | cut -f3 | tr -d '\r\n')

    # Query Acknowledgment module state
    CHOICE_INFO=$(moodle_query "SELECT id, availability FROM mdl_course_modules WHERE course=$COURSE_ID AND module=(SELECT id FROM mdl_modules WHERE name='choice') AND instance=(SELECT id FROM mdl_choice WHERE name='Policy Acknowledgment') LIMIT 1")
    CHOICE_ID=$(echo "$CHOICE_INFO" | cut -f1 | tr -d '\r\n')
    RAW_AVAILABILITY=$(echo "$CHOICE_INFO" | cut -f2)
    
    # Safely escape the JSON availability string for wrapping in our result JSON
    if [ "$RAW_AVAILABILITY" = "NULL" ] || [ -z "$RAW_AVAILABILITY" ]; then
        CHOICE_AVAILABILITY=""
    else
        CHOICE_AVAILABILITY=$(echo "$RAW_AVAILABILITY" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr -d '\n\r')
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": "$COURSE_ID",
    "guide_cmid": "$PAGE_ID",
    "guide_completion": "$PAGE_COMPLETION",
    "guide_completionview": "$PAGE_COMPLETIONVIEW",
    "acknowledgment_cmid": "$CHOICE_ID",
    "acknowledgment_availability": "$CHOICE_AVAILABILITY",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
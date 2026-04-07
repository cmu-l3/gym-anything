#!/bin/bash
echo "=== Exporting Feedback task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize JSON variables
FEEDBACK_EXISTS="false"
IS_ANONYMOUS="false"
NO_MULTIPLE_SUBMIT="false"
FEEDBACK_ID=""

# 1. Check if the feedback activity exists in the course
echo "Querying database for Feedback activity..."
FEEDBACK_DATA=$(moodle_query "SELECT f.id, f.anonymous, f.multiple_submit FROM mdl_feedback f JOIN mdl_course c ON f.course = c.id WHERE c.shortname = 'NURS-401' AND f.name = 'End of Course Evaluation' LIMIT 1")

if [ -n "$FEEDBACK_DATA" ]; then
    FEEDBACK_EXISTS="true"
    FEEDBACK_ID=$(echo "$FEEDBACK_DATA" | cut -f1)
    
    # In Moodle, anonymous: 1 = Anonymous, 2 = Log names
    F_ANON=$(echo "$FEEDBACK_DATA" | cut -f2)
    if [ "$F_ANON" = "1" ]; then
        IS_ANONYMOUS="true"
    fi
    
    # multiple_submit: 1 = Yes, 0 = No
    F_MULTI=$(echo "$FEEDBACK_DATA" | cut -f3)
    if [ "$F_MULTI" = "0" ]; then
        NO_MULTIPLE_SUBMIT="true"
    fi
    
    echo "Found feedback. ID: $FEEDBACK_ID, Anon: $F_ANON, Multi: $F_MULTI"
else
    echo "Feedback activity not found."
fi

# 2. Fetch all questions (items) for this feedback activity
ITEMS_JSON="[]"
if [ -n "$FEEDBACK_ID" ]; then
    moodle_query "SELECT typ, name, presentation FROM mdl_feedback_item WHERE feedback=$FEEDBACK_ID" > /tmp/f_items.txt
    
    # Parse items into a clean JSON array
    ITEMS_JSON=$(python3 -c '
import sys, json
items = []
try:
    with open("/tmp/f_items.txt", "r") as f:
        for line in f:
            parts = line.strip("\n").split("\t")
            if len(parts) >= 3:
                items.append({
                    "typ": parts[0], 
                    "name": parts[1], 
                    "presentation": parts[2]
                })
except Exception as e:
    pass
print(json.dumps(items))
')
fi

# Check task creation timestamp
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Write results to JSON payload
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "feedback_exists": $FEEDBACK_EXISTS,
    "is_anonymous": $IS_ANONYMOUS,
    "no_multiple_submit": $NO_MULTIPLE_SUBMIT,
    "feedback_items": $ITEMS_JSON
}
EOF

# Make result available to verifier
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="
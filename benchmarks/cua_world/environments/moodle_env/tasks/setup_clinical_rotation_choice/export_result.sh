#!/bin/bash
echo "=== Exporting Clinical Rotation Choice Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_CHOICE_COUNT=$(cat /tmp/initial_choice_count.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Initialize export variables
COURSE_ID=""
CHOICE_EXISTS="false"
CHOICE_CREATED_DURING_TASK="false"
CHOICE_NAME=""
LIMIT_ANSWERS="0"
SHOW_RESULTS="0"
OPTIONS_JSON="[]"

# Query the database
echo "Querying database for results..."

# 1. Get Course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='NURS101'" 2>/dev/null || echo "")

if [ -n "$COURSE_ID" ]; then
    # 2. Get the Choice Activity matching the expected name
    # Using case-insensitive LIKE to be slightly forgiving on exact case, verifier will strictly check
    CHOICE_DATA=$(moodle_query "SELECT id, name, limitanswers, showresults, timecreated FROM mdl_choice WHERE course=$COURSE_ID AND name LIKE '%Clinical Rotation%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$CHOICE_DATA" ]; then
        CHOICE_EXISTS="true"
        CHOICE_ID=$(echo "$CHOICE_DATA" | cut -f1)
        CHOICE_NAME=$(echo "$CHOICE_DATA" | cut -f2)
        LIMIT_ANSWERS=$(echo "$CHOICE_DATA" | cut -f3)
        SHOW_RESULTS=$(echo "$CHOICE_DATA" | cut -f4)
        TIME_CREATED=$(echo "$CHOICE_DATA" | cut -f5)
        
        # Check if created during task
        if [ "$TIME_CREATED" -ge "$TASK_START" ]; then
            CHOICE_CREATED_DURING_TASK="true"
        fi
        
        # 3. Get all options for this choice and convert to JSON
        OPTIONS_RAW=$(moodle_query "SELECT text, maxanswers FROM mdl_choice_options WHERE choiceid=$CHOICE_ID ORDER BY id ASC" 2>/dev/null)
        
        # Process options into a JSON array safely using Python
        OPTIONS_JSON=$(echo "$OPTIONS_RAW" | python3 -c '
import sys, json
options = []
for line in sys.stdin:
    line = line.strip("\n")
    if not line: continue
    parts = line.split("\t")
    if len(parts) >= 2:
        options.append({"text": parts[0].strip(), "limit": int(parts[1])})
print(json.dumps(options))
' 2>/dev/null || echo "[]")

    fi
fi

# Check if Firefox was left open
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "course_found": $([ -n "$COURSE_ID" ] && echo "true" || echo "false"),
    "choice_exists": $CHOICE_EXISTS,
    "choice_created_during_task": $CHOICE_CREATED_DURING_TASK,
    "choice_name": "$(echo "$CHOICE_NAME" | sed 's/"/\\"/g')",
    "limit_answers": $LIMIT_ANSWERS,
    "show_results": $SHOW_RESULTS,
    "options": $OPTIONS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
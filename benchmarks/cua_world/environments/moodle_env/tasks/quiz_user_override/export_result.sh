#!/bin/bash
set -e
echo "=== Exporting Quiz User Override Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Query Database for Quiz and Override states
# 1. Get Quiz ID
QUIZ_ID=$(moodle_query "SELECT id FROM mdl_quiz WHERE name='Midterm Examination' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")

# 2. Get User ID
USER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='awilson' LIMIT 1" 2>/dev/null || echo "")

# 3. Retrieve Global Quiz Settings
GLOBAL_TIMELIMIT=0
if [ -n "$QUIZ_ID" ]; then
    GLOBAL_TIMELIMIT=$(moodle_query "SELECT timelimit FROM mdl_quiz WHERE id=$QUIZ_ID" 2>/dev/null || echo "0")
fi

# 4. Retrieve Override Settings
OVERRIDE_EXISTS="false"
OVERRIDE_TIMELIMIT=0
OVERRIDE_TIMECLOSE=0

if [ -n "$QUIZ_ID" ] && [ -n "$USER_ID" ]; then
    # Look for an override for this specific user on this specific quiz
    OVERRIDE_RECORD=$(moodle_query "SELECT timelimit, timeclose FROM mdl_quiz_overrides WHERE quiz=$QUIZ_ID AND userid=$USER_ID LIMIT 1" 2>/dev/null || echo "")
    
    if [ -n "$OVERRIDE_RECORD" ]; then
        OVERRIDE_EXISTS="true"
        OVERRIDE_TIMELIMIT=$(echo "$OVERRIDE_RECORD" | awk '{print $1}')
        OVERRIDE_TIMECLOSE=$(echo "$OVERRIDE_RECORD" | awk '{print $2}')
    fi
fi

# Check if any browser is running
BROWSER_RUNNING=$(pgrep -f "firefox|chrome|chromium" > /dev/null && echo "true" || echo "false")

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "quiz_found": $(if [ -n "$QUIZ_ID" ]; then echo "true"; else echo "false"; fi),
    "user_found": $(if [ -n "$USER_ID" ]; then echo "true"; else echo "false"; fi),
    "global_timelimit": $GLOBAL_TIMELIMIT,
    "override_exists": $OVERRIDE_EXISTS,
    "override_timelimit": ${OVERRIDE_TIMELIMIT:-0},
    "override_timeclose": ${OVERRIDE_TIMECLOSE:-0},
    "browser_running": $BROWSER_RUNNING
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
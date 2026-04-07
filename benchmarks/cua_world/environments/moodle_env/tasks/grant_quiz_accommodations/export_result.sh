#!/bin/bash
echo "=== Exporting grant_quiz_accommodations results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract core quiz configuration to ensure base settings were NOT modified
QUIZ_DATA=$(moodle_query "SELECT id, timelimit, attempts FROM mdl_quiz WHERE name='Midterm Examination' LIMIT 1")
QUIZ_ID=$(echo "$QUIZ_DATA" | cut -f1)
BASE_TIMELIMIT=$(echo "$QUIZ_DATA" | cut -f2)
BASE_ATTEMPTS=$(echo "$QUIZ_DATA" | cut -f3)

# Extract Alice's Override Data
ALICE_DATA=$(moodle_query "SELECT o.timelimit, o.attempts, o.id FROM mdl_quiz_overrides o JOIN mdl_user u ON o.userid = u.id WHERE o.quiz = '$QUIZ_ID' AND u.username = 'awilson' LIMIT 1")
ALICE_TIMELIMIT=$(echo "$ALICE_DATA" | cut -f1)
ALICE_ATTEMPTS=$(echo "$ALICE_DATA" | cut -f2)
ALICE_OVERRIDE_ID=$(echo "$ALICE_DATA" | cut -f3)

# Extract Bob's Override Data
BOB_DATA=$(moodle_query "SELECT o.timelimit, o.attempts, o.id FROM mdl_quiz_overrides o JOIN mdl_user u ON o.userid = u.id WHERE o.quiz = '$QUIZ_ID' AND u.username = 'bbrown' LIMIT 1")
BOB_TIMELIMIT=$(echo "$BOB_DATA" | cut -f1)
BOB_ATTEMPTS=$(echo "$BOB_DATA" | cut -f2)
BOB_OVERRIDE_ID=$(echo "$BOB_DATA" | cut -f3)

# Build JSON Result File
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "quiz": {
        "id": "${QUIZ_ID:-null}",
        "base_timelimit": "${BASE_TIMELIMIT:-null}",
        "base_attempts": "${BASE_ATTEMPTS:-null}"
    },
    "overrides": {
        "alice": {
            "found": $([ -n "$ALICE_OVERRIDE_ID" ] && echo "true" || echo "false"),
            "timelimit": "${ALICE_TIMELIMIT:-null}",
            "attempts": "${ALICE_ATTEMPTS:-null}"
        },
        "bob": {
            "found": $([ -n "$BOB_OVERRIDE_ID" ] && echo "true" || echo "false"),
            "timelimit": "${BOB_TIMELIMIT:-null}",
            "attempts": "${BOB_ATTEMPTS:-null}"
        }
    }
}
EOF

# Safely copy to /tmp to avoid permission errors
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
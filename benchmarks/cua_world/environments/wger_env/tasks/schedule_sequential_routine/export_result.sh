#!/bin/bash
echo "=== Exporting schedule_sequential_routine task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Record basic timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Fetch initial and current routine counts
INITIAL_COUNT=$(cat /tmp/initial_routine_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(db_query "SELECT COUNT(*) FROM manager_routine" 2>/dev/null || echo "0")

# 4. Fetch the end date of the target routine and the original assigned date (anti-tampering check)
BEGINNER_END=$(db_query "SELECT \"end\" FROM manager_routine WHERE name = '5x5 Beginner' LIMIT 1" 2>/dev/null)
ORIGINAL_END=$(cat /tmp/original_end_date.txt 2>/dev/null || echo "")

# 5. Fetch the start date of the newly created routine (if it exists)
NEW_ROUTINE_START=$(db_query "SELECT \"start\" FROM manager_routine WHERE name = 'Intermediate Hypertrophy' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# 6. Save results to JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "beginner_end": "$BEGINNER_END",
    "original_end": "$ORIGINAL_END",
    "new_routine_start": "$NEW_ROUTINE_START"
}
EOF

# Move to final location ensuring proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
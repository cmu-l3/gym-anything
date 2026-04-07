#!/bin/bash
echo "=== Exporting delete_weight_entries task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Retrieve initial counts
if [ -f /tmp/initial_counts.json ]; then
    INITIAL_TOTAL=$(grep -o '"initial_total": [0-9]*' /tmp/initial_counts.json | awk '{print $2}')
    INITIAL_ERRONEOUS=$(grep -o '"initial_erroneous": [0-9]*' /tmp/initial_counts.json | awk '{print $2}')
    INITIAL_CORRECT=$(grep -o '"initial_correct": [0-9]*' /tmp/initial_counts.json | awk '{print $2}')
else
    INITIAL_TOTAL=33
    INITIAL_ERRONEOUS=3
    INITIAL_CORRECT=30
fi

# Query current database state
ADMIN_ID=$(db_query "SELECT id FROM auth_user WHERE username='admin'" || echo "1")
CURRENT_TOTAL=$(db_query "SELECT COUNT(*) FROM weight_weightentry WHERE user_id=${ADMIN_ID}")
CURRENT_ERRONEOUS=$(db_query "SELECT COUNT(*) FROM weight_weightentry WHERE user_id=${ADMIN_ID} AND weight > 150")
CURRENT_CORRECT=$(db_query "SELECT COUNT(*) FROM weight_weightentry WHERE user_id=${ADMIN_ID} AND weight <= 150")

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_total": $INITIAL_TOTAL,
    "initial_erroneous": $INITIAL_ERRONEOUS,
    "initial_correct": $INITIAL_CORRECT,
    "current_total": $CURRENT_TOTAL,
    "current_erroneous": $CURRENT_ERRONEOUS,
    "current_correct": $CURRENT_CORRECT,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="
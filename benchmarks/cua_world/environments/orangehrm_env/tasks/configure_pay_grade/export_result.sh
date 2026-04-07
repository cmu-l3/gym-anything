#!/bin/bash
set -e
echo "=== Exporting configure_pay_grade results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_paygrade_id.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Results
# Check if Pay Grade exists
PG_DATA=$(orangehrm_db_query "SELECT id, name FROM ohrm_pay_grade WHERE name = 'Grade HC-4' LIMIT 1;")
PG_ID=$(echo "$PG_DATA" | awk '{print $1}')
PG_NAME=$(echo "$PG_DATA" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')

PG_EXISTS="false"
PG_CREATED_DURING_TASK="false"
CURRENCY_EXISTS="false"
MIN_SALARY="0"
MAX_SALARY="0"

if [ -n "$PG_ID" ]; then
    PG_EXISTS="true"
    
    # Anti-gaming check: ID should be new
    if [ "$PG_ID" -gt "$INITIAL_MAX_ID" ]; then
        PG_CREATED_DURING_TASK="true"
    fi

    # Check for Currency Configuration
    # We look for USD specifically linked to this pay grade
    CURRENCY_DATA=$(orangehrm_db_query "SELECT min_salary, max_salary FROM ohrm_pay_grade_currency WHERE pay_grade_id = ${PG_ID} AND currency_id = 'USD' LIMIT 1;")
    
    if [ -n "$CURRENCY_DATA" ]; then
        CURRENCY_EXISTS="true"
        MIN_SALARY=$(echo "$CURRENCY_DATA" | awk '{print $1}')
        MAX_SALARY=$(echo "$CURRENCY_DATA" | awk '{print $2}')
    fi
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_max_id": $INITIAL_MAX_ID,
    "pay_grade_exists": $PG_EXISTS,
    "pay_grade_id": "${PG_ID:-0}",
    "pay_grade_name": "${PG_NAME:-}",
    "created_during_task": $PG_CREATED_DURING_TASK,
    "currency_exists": $CURRENCY_EXISTS,
    "found_min_salary": ${MIN_SALARY:-0},
    "found_max_salary": ${MAX_SALARY:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
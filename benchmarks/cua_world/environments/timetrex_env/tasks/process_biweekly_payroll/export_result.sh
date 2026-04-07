#!/bin/bash
# Export script for Process Bi-Weekly Payroll task
# Safely extracts database state changes after the agent concludes

echo "=== Exporting Process Bi-Weekly Payroll Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions
if ! type timetrex_query &>/dev/null; then
    timetrex_query() {
        docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "$1" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    }
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Ensure database is reachable
if ! docker exec timetrex-postgres pg_isready -U timetrex -d timetrex 2>/dev/null; then
    echo "FATAL: Database not accessible. Creating failure result."
    cat > /tmp/payroll_result.json << EOF
{
    "error": "Database container not reachable",
    "export_timestamp": "$(date -Iseconds)"
}
EOF
    chmod 666 /tmp/payroll_result.json 2>/dev/null || true
    exit 0
fi

# Load initial parameters
INITIAL_COUNT=$(cat /tmp/initial_pay_stub_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Fetch current pay stub count
CURRENT_COUNT=$(timetrex_query "SELECT COUNT(*) FROM pay_stub" 2>/dev/null || echo "0")

# Query to find if a pay period was processed DURING the task execution
# 10 = Open, 20 = Processed, 22 = Closed
# We look for any pay period updated after TASK_START whose status is no longer Open (10)
PROCESSED_SCHEDULE_NAME=$(timetrex_query "
    SELECT pps.name
    FROM pay_period pp
    JOIN pay_period_schedule pps ON pp.pay_period_schedule_id = pps.id
    WHERE pp.updated_date >= $TASK_START
      AND pp.status_id IN (20, 22)
    ORDER BY pp.updated_date DESC
    LIMIT 1;
" 2>/dev/null)

if [ -z "$PROCESSED_SCHEDULE_NAME" ]; then
    PROCESSED_SCHEDULE_NAME="None"
fi

echo "Initial Stubs: $INITIAL_COUNT | Current Stubs: $CURRENT_COUNT"
echo "Recently Processed Schedule: $PROCESSED_SCHEDULE_NAME"

# Export result to JSON
TEMP_JSON=$(mktemp /tmp/payroll_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_stub_count": ${INITIAL_COUNT:-0},
    "current_stub_count": ${CURRENT_COUNT:-0},
    "processed_schedule": "${PROCESSED_SCHEDULE_NAME}",
    "task_start_timestamp": ${TASK_START:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/payroll_result.json 2>/dev/null || sudo rm -f /tmp/payroll_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/payroll_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/payroll_result.json
chmod 666 /tmp/payroll_result.json 2>/dev/null || sudo chmod 666 /tmp/payroll_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/payroll_result.json"
cat /tmp/payroll_result.json

echo "=== Export Complete ==="
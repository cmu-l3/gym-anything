#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results: create_accounting_journal ==="

# 1. Capture final screenshot (visual evidence)
take_screenshot /tmp/task_final_state.png

# 2. Retrieve verification data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_journal_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM journals;" 2>/dev/null || echo "0")

# 3. Check for the specific journal in the database
# We fetch relevant fields for the journal with code 'SUBV'
# Format: id|name|nature|currency|created_at_epoch
JOURNAL_DATA=$(ekylibre_db_query "SELECT id, name, nature, currency, EXTRACT(EPOCH FROM created_at)::integer FROM journals WHERE code = 'SUBV' LIMIT 1;")

# Parse the result
JOURNAL_FOUND="false"
JOURNAL_NAME=""
JOURNAL_NATURE=""
JOURNAL_CURRENCY=""
JOURNAL_CREATED_AT="0"

if [ -n "$JOURNAL_DATA" ]; then
    JOURNAL_FOUND="true"
    JOURNAL_NAME=$(echo "$JOURNAL_DATA" | cut -d'|' -f2)
    JOURNAL_NATURE=$(echo "$JOURNAL_DATA" | cut -d'|' -f3)
    JOURNAL_CURRENCY=$(echo "$JOURNAL_DATA" | cut -d'|' -f4)
    JOURNAL_CREATED_AT=$(echo "$JOURNAL_DATA" | cut -d'|' -f5)
fi

# 4. Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_journal_count": $INITIAL_COUNT,
    "final_journal_count": $FINAL_COUNT,
    "journal_found": $JOURNAL_FOUND,
    "journal_data": {
        "name": "$JOURNAL_NAME",
        "nature": "$JOURNAL_NATURE",
        "currency": "$JOURNAL_CURRENCY",
        "created_at": $JOURNAL_CREATED_AT
    },
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# 5. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
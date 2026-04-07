#!/bin/bash
set -e
echo "=== Exporting retire_concept results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_UUID=$(cat /tmp/target_concept_uuid.txt 2>/dev/null)

if [ -z "$TARGET_UUID" ]; then
    echo "ERROR: Target UUID file missing."
    TARGET_UUID=""
fi

# ── Query Database for Concept State ──────────────────────────────────────────
echo "Querying database for concept state..."

# We select explicit fields to verify retirement details
# format: retired | retire_reason | date_retired (unix timestamp) | uuid
SQL="SELECT retired, retire_reason, UNIX_TIMESTAMP(date_retired), uuid FROM concept WHERE uuid = '$TARGET_UUID';"
DB_RESULT=$(omrs_db_query "$SQL")

# Parse result (tab separated)
RETIRED_VAL=$(echo "$DB_RESULT" | cut -f1)
REASON_VAL=$(echo "$DB_RESULT" | cut -f2)
DATE_VAL=$(echo "$DB_RESULT" | cut -f3)
UUID_VAL=$(echo "$DB_RESULT" | cut -f4)

# Normalize boolean
IS_RETIRED="false"
if [ "$RETIRED_VAL" == "1" ] || [ "$RETIRED_VAL" == "true" ]; then
    IS_RETIRED="true"
fi

# Check if concept was purged (result empty)
CONCEPT_EXISTS="true"
if [ -z "$DB_RESULT" ]; then
    CONCEPT_EXISTS="false"
fi

# ── Anti-Gaming Checks ────────────────────────────────────────────────────────
# Check if date_retired is valid and after task start
DATE_VALID="false"
if [ -n "$DATE_VAL" ] && [ "$DATE_VAL" != "NULL" ]; then
    if [ "$DATE_VAL" -ge "$TASK_START" ]; then
        DATE_VALID="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# ── Export JSON ──────────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_uuid": "$TARGET_UUID",
    "concept_exists": $CONCEPT_EXISTS,
    "is_retired": $IS_RETIRED,
    "retire_reason": "$(echo "$REASON_VAL" | sed 's/"/\\"/g')",
    "date_retired_timestamp": "${DATE_VAL:-0}",
    "retired_during_task": $DATE_VALID,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="
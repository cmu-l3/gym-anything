#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_custom_tax results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_TAX_COUNT=$(cat /tmp/initial_tax_count.txt 2>/dev/null || echo "0")
TENANT_SCHEMA=$(cat /tmp/ekylibre_tenant_schema.txt 2>/dev/null || echo "")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare DB query prefix
SP=""
if [ -n "$TENANT_SCHEMA" ]; then
    SP="SET search_path TO \"$TENANT_SCHEMA\", public;"
fi

# 1. Get current tax count
CURRENT_TAX_COUNT=$(ekylibre_db_query "$SP SELECT COUNT(*) FROM taxes;" | tr -d '[:space:]')
CURRENT_TAX_COUNT=${CURRENT_TAX_COUNT:-0}

# 2. Search for the specific tax created during the task
# We look for a tax created after TASK_START with rate 5.5
# Note: created_at is in UTC, we use EXTRACT(EPOCH) for comparison
TAX_QUERY="
SELECT row_to_json(t)
FROM (
    SELECT name, amount, country, nature, EXTRACT(EPOCH FROM created_at) as created_epoch
    FROM taxes
    WHERE EXTRACT(EPOCH FROM created_at) >= $TASK_START
    ORDER BY created_at DESC
    LIMIT 1
) t;
"
NEW_TAX_JSON=$(ekylibre_db_query "$SP $TAX_QUERY")

# 3. Fallback: If no timestamp match, look for name/rate match generally
# (In case clock skew issues, though rare in Docker)
if [ -z "$NEW_TAX_JSON" ]; then
    TAX_QUERY_FALLBACK="
    SELECT row_to_json(t)
    FROM (
        SELECT name, amount, country, nature, EXTRACT(EPOCH FROM created_at) as created_epoch
        FROM taxes
        WHERE (amount = 5.5 OR amount = 0.055)
        ORDER BY id DESC
        LIMIT 1
    ) t;
    "
    NEW_TAX_JSON=$(ekylibre_db_query "$SP $TAX_QUERY_FALLBACK")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_tax_count": $INITIAL_TAX_COUNT,
    "current_tax_count": $CURRENT_TAX_COUNT,
    "new_tax_record": ${NEW_TAX_JSON:-null},
    "tenant_schema": "$TENANT_SCHEMA",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
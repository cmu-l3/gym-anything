#!/bin/bash
# Export script for Add Billing Service Code task

echo "=== Exporting results ==="

source /workspace/scripts/task_utils.sh

# 1. Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture final screenshot
take_screenshot /tmp/task_final.png

# 3. Query the database for the created code
# We select relevant fields: service_code, unit_price, description, status (if avail)
# Note: Schema might vary slightly, so we select standard fields.
echo "Querying database for code K083..."

# Using oscar_query wrapper from task_utils which runs docker exec
# We use a separator '|' to parse easily in python
DB_RESULT=$(oscar_query "SELECT service_code, unit_price, service_desc FROM billing_service WHERE service_code='K083' LIMIT 1" | sed 's/\t/|/g')

# 4. Check if we found anything
CODE_EXISTS="false"
FOUND_CODE=""
FOUND_PRICE="0"
FOUND_DESC=""

if [ -n "$DB_RESULT" ]; then
    CODE_EXISTS="true"
    # Parse the result (assuming format: K083|45.00|Description)
    FOUND_CODE=$(echo "$DB_RESULT" | cut -d'|' -f1)
    FOUND_PRICE=$(echo "$DB_RESULT" | cut -d'|' -f2)
    FOUND_DESC=$(echo "$DB_RESULT" | cut -d'|' -f3)
fi

# 5. Create JSON result
# We use a temp file to avoid permission issues during creation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "code_exists": $CODE_EXISTS,
    "found_data": {
        "service_code": "$FOUND_CODE",
        "unit_price": "$FOUND_PRICE",
        "description": "$FOUND_DESC"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json
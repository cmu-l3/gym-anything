#!/bin/bash
echo "=== Exporting configure_payment_term result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the created payment term
# specific value: 2-10-Net-45
echo "--- Querying database for Payment Term '2-10-Net-45' ---"

# We fetch relevant columns. 
# Note: iDempiere timestamps in DB might differ from system time slightly, 
# but we check if record exists and its properties.
QUERY="SELECT value, name, description, discount, discountdays, netdays, isvalid, isactive, created 
       FROM c_paymentterm 
       WHERE value='2-10-Net-45' 
       ORDER BY created DESC LIMIT 1"

# Run query using docker exec
# Use -x to disable expanded output, -A for no alignment, -t for tuples only, 
# but since we want JSON-like parsing, we'll use a separator.
# Actually, let's output raw values separated by pipes for easy parsing
RAW_DATA=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -F "|" -c "$QUERY" 2>/dev/null || echo "")

echo "Raw DB Data: $RAW_DATA"

FOUND="false"
VAL_SEARCH_KEY=""
VAL_NAME=""
VAL_DESC=""
VAL_DISCOUNT="0"
VAL_DISCOUNT_DAYS="0"
VAL_NET_DAYS="0"
VAL_IS_VALID="N"
VAL_IS_ACTIVE="N"
VAL_CREATED=""

if [ -n "$RAW_DATA" ]; then
    FOUND="true"
    VAL_SEARCH_KEY=$(echo "$RAW_DATA" | cut -d'|' -f1)
    VAL_NAME=$(echo "$RAW_DATA" | cut -d'|' -f2)
    VAL_DESC=$(echo "$RAW_DATA" | cut -d'|' -f3)
    VAL_DISCOUNT=$(echo "$RAW_DATA" | cut -d'|' -f4)
    VAL_DISCOUNT_DAYS=$(echo "$RAW_DATA" | cut -d'|' -f5)
    VAL_NET_DAYS=$(echo "$RAW_DATA" | cut -d'|' -f6)
    VAL_IS_VALID=$(echo "$RAW_DATA" | cut -d'|' -f7)
    VAL_IS_ACTIVE=$(echo "$RAW_DATA" | cut -d'|' -f8)
    VAL_CREATED=$(echo "$RAW_DATA" | cut -d'|' -f9)
fi

# Get current count
CURRENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_paymentterm" 2>/dev/null || echo "0")

# Check if application was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "record_found": $FOUND,
    "record": {
        "search_key": "$VAL_SEARCH_KEY",
        "name": "$VAL_NAME",
        "description": "$VAL_DESC",
        "discount": "$VAL_DISCOUNT",
        "discount_days": "$VAL_DISCOUNT_DAYS",
        "net_days": "$VAL_NET_DAYS",
        "is_valid": "$VAL_IS_VALID",
        "is_active": "$VAL_IS_ACTIVE",
        "created": "$VAL_CREATED"
    },
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
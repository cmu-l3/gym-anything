#!/bin/bash
# Export script for Gift Message Workflow task

echo "=== Exporting Gift Message Workflow Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get Config Status
CONFIG_VALUE=$(magento_query "SELECT value FROM core_config_data WHERE path='sales/gift_options/allow_order'" 2>/dev/null | tail -1 | tr -d '[:space:]')
echo "Config value (sales/gift_options/allow_order): $CONFIG_VALUE"

# 2. Get Order Data
TARGET_EMAIL="test.gift@example.com"
ORDER_DATA=$(magento_query "SELECT entity_id, increment_id, gift_message_id, created_at FROM sales_order WHERE customer_email='$TARGET_EMAIL' ORDER BY entity_id DESC LIMIT 1" 2>/dev/null | tail -1)

ORDER_ID=$(echo "$ORDER_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
INCREMENT_ID=$(echo "$ORDER_DATA" | awk -F'\t' '{print $2}')
GIFT_MESSAGE_ID=$(echo "$ORDER_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
CREATED_AT=$(echo "$ORDER_DATA" | awk -F'\t' '{print $4}')

ORDER_FOUND="false"
[ -n "$ORDER_ID" ] && ORDER_FOUND="true"

echo "Order found: $ORDER_FOUND (ID=$ORDER_ID, Increment=$INCREMENT_ID)"
echo "Gift Message ID: $GIFT_MESSAGE_ID"

# 3. Get Gift Message Content
MESSAGE_SENDER=""
MESSAGE_RECIPIENT=""
MESSAGE_TEXT=""

if [ -n "$GIFT_MESSAGE_ID" ] && [ "$GIFT_MESSAGE_ID" != "NULL" ]; then
    MSG_DATA=$(magento_query "SELECT sender, recipient, message FROM gift_message WHERE message_id=$GIFT_MESSAGE_ID" 2>/dev/null | tail -1)
    # Be careful with parsing message text as it might contain tabs or spaces
    # Using python to fetch safely might be better, but we stick to bash/mysql -B for now
    MESSAGE_SENDER=$(echo "$MSG_DATA" | awk -F'\t' '{print $1}')
    MESSAGE_RECIPIENT=$(echo "$MSG_DATA" | awk -F'\t' '{print $2}')
    MESSAGE_TEXT=$(echo "$MSG_DATA" | awk -F'\t' '{print $3}')
fi

echo "Message: From '$MESSAGE_SENDER' To '$MESSAGE_RECIPIENT' Body: '$MESSAGE_TEXT'"

# 4. Count Checks
INITIAL_ORDER_COUNT=$(cat /tmp/initial_order_count 2>/dev/null || echo "0")
CURRENT_ORDER_COUNT=$(get_order_count 2>/dev/null || echo "0")
ORDER_COUNT_INCREASED="false"
if [ "$CURRENT_ORDER_COUNT" -gt "$INITIAL_ORDER_COUNT" ]; then
    ORDER_COUNT_INCREASED="true"
fi

# 5. App State Check
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Escape for JSON
SENDER_ESC=$(echo "$MESSAGE_SENDER" | sed 's/"/\\"/g')
RECIPIENT_ESC=$(echo "$MESSAGE_RECIPIENT" | sed 's/"/\\"/g')
TEXT_ESC=$(echo "$MESSAGE_TEXT" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/gift_message_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config_value": "${CONFIG_VALUE:-0}",
    "order_found": $ORDER_FOUND,
    "order_id": "${ORDER_ID:-}",
    "increment_id": "${INCREMENT_ID:-}",
    "gift_message_id": "${GIFT_MESSAGE_ID:-}",
    "message_sender": "$SENDER_ESC",
    "message_recipient": "$RECIPIENT_ESC",
    "message_text": "$TEXT_ESC",
    "initial_order_count": ${INITIAL_ORDER_COUNT:-0},
    "current_order_count": ${CURRENT_ORDER_COUNT:-0},
    "order_count_increased": $ORDER_COUNT_INCREASED,
    "app_running": $APP_RUNNING,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/gift_message_result.json

echo ""
cat /tmp/gift_message_result.json
echo ""
echo "=== Export Complete ==="
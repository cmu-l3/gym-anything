#!/bin/bash
echo "=== Exporting Inventory Settings Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to get option value
get_opt() {
    wc_query "SELECT option_value FROM wp_options WHERE option_name='$1' LIMIT 1"
}

# Collect current values
VAL_MANAGE_STOCK=$(get_opt "woocommerce_manage_stock")
VAL_HOLD_STOCK=$(get_opt "woocommerce_hold_stock_minutes")
VAL_NOTIFY_LOW=$(get_opt "woocommerce_notify_low_stock")
VAL_NOTIFY_NO=$(get_opt "woocommerce_notify_no_stock")
VAL_RECIPIENT=$(get_opt "woocommerce_stock_email_recipient")
VAL_LOW_AMOUNT=$(get_opt "woocommerce_notify_low_stock_amount")
VAL_NO_AMOUNT=$(get_opt "woocommerce_notify_no_stock_amount")
VAL_HIDE_OOS=$(get_opt "woocommerce_hide_out_of_stock_items")
VAL_FORMAT=$(get_opt "woocommerce_stock_format")

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "settings": {
        "woocommerce_manage_stock": "$(json_escape "$VAL_MANAGE_STOCK")",
        "woocommerce_hold_stock_minutes": "$(json_escape "$VAL_HOLD_STOCK")",
        "woocommerce_notify_low_stock": "$(json_escape "$VAL_NOTIFY_LOW")",
        "woocommerce_notify_no_stock": "$(json_escape "$VAL_NOTIFY_NO")",
        "woocommerce_stock_email_recipient": "$(json_escape "$VAL_RECIPIENT")",
        "woocommerce_notify_low_stock_amount": "$(json_escape "$VAL_LOW_AMOUNT")",
        "woocommerce_notify_no_stock_amount": "$(json_escape "$VAL_NO_AMOUNT")",
        "woocommerce_hide_out_of_stock_items": "$(json_escape "$VAL_HIDE_OOS")",
        "woocommerce_stock_format": "$(json_escape "$VAL_FORMAT")"
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
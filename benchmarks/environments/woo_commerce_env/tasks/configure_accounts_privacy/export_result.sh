#!/bin/bash
set -e
echo "=== Exporting configure_accounts_privacy result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
take_screenshot /tmp/task_final_state.png

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Query current values for all target options
echo "Querying final option values..."

GUEST_CHECKOUT=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='woocommerce_enable_guest_checkout' LIMIT 1")
LOGIN_REMINDER=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='woocommerce_enable_checkout_login_reminder' LIMIT 1")
CHECKOUT_SIGNUP=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='woocommerce_enable_signup_and_login_from_checkout' LIMIT 1")
MYACCOUNT_SIGNUP=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='woocommerce_enable_myaccount_registration' LIMIT 1")
ERASE_ORDERS=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='woocommerce_erasure_request_removes_order_data' LIMIT 1")
ERASE_DOWNLOADS=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='woocommerce_erasure_request_removes_download_data' LIMIT 1")

# Get initial values for comparison (anti-gaming)
INITIAL_JSON="/tmp/initial_account_settings.json"
INITIAL_GUEST="unknown"
if [ -f "$INITIAL_JSON" ]; then
    # Simple grep extraction since we don't have jq in all base envs, though woo_env usually has it.
    # Using python for safety
    INITIAL_GUEST=$(python3 -c "import json; print(json.load(open('$INITIAL_JSON')).get('guest_checkout', ''))" 2>/dev/null || echo "unknown")
fi

# Check timestamps to verify recent activity
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "final_state": {
        "woocommerce_enable_guest_checkout": "${GUEST_CHECKOUT:-unknown}",
        "woocommerce_enable_checkout_login_reminder": "${LOGIN_REMINDER:-unknown}",
        "woocommerce_enable_signup_and_login_from_checkout": "${CHECKOUT_SIGNUP:-unknown}",
        "woocommerce_enable_myaccount_registration": "${MYACCOUNT_SIGNUP:-unknown}",
        "woocommerce_erasure_request_removes_order_data": "${ERASE_ORDERS:-unknown}",
        "woocommerce_erasure_request_removes_download_data": "${ERASE_DOWNLOADS:-unknown}"
    },
    "initial_state_file_exists": $([ -f "$INITIAL_JSON" ] && echo "true" || echo "false"),
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $CURRENT_TIME
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="
#!/bin/bash
# Export script for GDPR Data Erasure task

echo "=== Exporting GDPR Data Erasure Result ==="

source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/gdpr_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load Task Data
ORDER_ID=$(cat /tmp/target_order_id.txt 2>/dev/null)
TARGET_EMAIL="sarah.connor.privacy@example.com"

# 1. Check Privacy Setting
# Expected: "yes" (1)
PRIVACY_SETTING=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='woocommerce_erasure_request_removes_order_data'")
echo "Privacy Setting Value: $PRIVACY_SETTING"

# 2. Check User Existence
# Expected: Empty (User should be deleted)
USER_EXISTS=$(wc_query "SELECT ID FROM wp_users WHERE user_email='$TARGET_EMAIL'")
if [ -z "$USER_EXISTS" ]; then
    echo "User $TARGET_EMAIL deleted successfully."
    USER_DELETED="true"
else
    echo "User $TARGET_EMAIL still exists (ID: $USER_EXISTS)."
    USER_DELETED="false"
fi

# 3. Check Order Anonymization
# Expected: _billing_email should NOT be the original email.
# It usually becomes "removed@..." or similar when anonymized.
ORDER_EMAIL=""
ORDER_ANONYMIZED="false"

if [ -n "$ORDER_ID" ]; then
    ORDER_EMAIL=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ORDER_ID AND meta_key='_billing_email'")
    echo "Order $ORDER_ID email is now: $ORDER_EMAIL"
    
    if [ "$ORDER_EMAIL" != "$TARGET_EMAIL" ]; then
        # Double check it isn't just empty (unless that's the anonymization method, but WC usually replaces it)
        # However, strictly speaking, if it doesn't match the PII, it's anonymized.
        ORDER_ANONYMIZED="true"
    fi
else
    echo "WARNING: Target Order ID not found in temp file."
fi

# 4. Check Timestamp of actions (Anti-gaming)
# We check if the order was modified AFTER the task started.
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORDER_MODIFIED_TS=0

if [ -n "$ORDER_ID" ]; then
    ORDER_MODIFIED_STR=$(wc_query "SELECT post_modified_gmt FROM wp_posts WHERE ID=$ORDER_ID")
    if [ -n "$ORDER_MODIFIED_STR" ]; then
        ORDER_MODIFIED_TS=$(date -d "$ORDER_MODIFIED_STR" +%s)
    fi
fi

ACTION_DURING_TASK="false"
if [ "$ORDER_MODIFIED_TS" -gt "$TASK_START" ]; then
    ACTION_DURING_TASK="true"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/gdpr_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "privacy_setting_value": "$(json_escape "$PRIVACY_SETTING")",
    "user_deleted": $USER_DELETED,
    "order_anonymized": $ORDER_ANONYMIZED,
    "final_order_email": "$(json_escape "$ORDER_EMAIL")",
    "action_occurred_during_task": $ACTION_DURING_TASK,
    "task_start_ts": $TASK_START,
    "order_modified_ts": $ORDER_MODIFIED_TS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/gdpr_result.json

echo ""
cat /tmp/gdpr_result.json
echo ""
echo "=== Export Complete ==="
#!/bin/bash
# Export script for Session Persistence Configuration task

echo "=== Exporting Session Persistence Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Function to get config value and updated_at timestamp
# Returns JSON object: {"value": "...", "updated_at": "..."}
get_config_details() {
    local path="$1"
    # Query database directly for value and timestamp
    local result=$(magento_query "SELECT value, updated_at FROM core_config_data WHERE path='$path' ORDER BY config_id DESC LIMIT 1")
    
    if [ -z "$result" ]; then
        echo '{"value": null, "updated_at": null}'
    else
        local val=$(echo "$result" | cut -f1)
        local time=$(echo "$result" | cut -f2)
        # Escape quotes in value
        val=$(echo "$val" | sed 's/"/\\"/g')
        echo "{\"value\": \"$val\", \"updated_at\": \"$time\"}"
    fi
}

# Fetch all relevant config settings
COOKIE_LIFETIME=$(get_config_details "web/cookie/cookie_lifetime")
PERSIST_ENABLED=$(get_config_details "persistent/options/enabled")
PERSIST_LIFETIME=$(get_config_details "persistent/options/lifetime")
REMEMBER_ENABLED=$(get_config_details "persistent/options/remember_enabled")
REMEMBER_DEFAULT=$(get_config_details "persistent/options/remember_default")
LOGOUT_CLEAR=$(get_config_details "persistent/options/logout_clear")
PERSIST_CART=$(get_config_details "persistent/options/shopping_cart")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/session_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": "$TASK_START_TIME",
    "configs": {
        "web/cookie/cookie_lifetime": $COOKIE_LIFETIME,
        "persistent/options/enabled": $PERSIST_ENABLED,
        "persistent/options/lifetime": $PERSIST_LIFETIME,
        "persistent/options/remember_enabled": $REMEMBER_ENABLED,
        "persistent/options/remember_default": $REMEMBER_DEFAULT,
        "persistent/options/logout_clear": $LOGOUT_CLEAR,
        "persistent/options/shopping_cart": $PERSIST_CART
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/session_config_result.json

echo "Result exported:"
cat /tmp/session_config_result.json
echo "=== Export Complete ==="
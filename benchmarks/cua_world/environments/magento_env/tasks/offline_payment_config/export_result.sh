#!/bin/bash
# Export script for Offline Payment Configuration task

echo "=== Exporting Payment Config Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Helper function to get config value
get_config() {
    local path="$1"
    # Use magento_query but ensure we get the value cleanly
    # Note: magento_query returns raw output, sometimes with warnings if not suppressed
    # The grep/head/tail ensures we get the DB value
    magento_query "SELECT value FROM core_config_data WHERE path='$path'" 2>/dev/null | tail -1
}

# --- 1. Bank Transfer Config ---
BANK_ACTIVE=$(get_config "payment/banktransfer/active")
BANK_TITLE=$(get_config "payment/banktransfer/title")
BANK_INSTRUCTIONS=$(get_config "payment/banktransfer/instructions")
BANK_SORT=$(get_config "payment/banktransfer/sort_order")

# --- 2. Check/Money Order Config ---
CHECK_ACTIVE=$(get_config "payment/checkmo/active")
CHECK_TITLE=$(get_config "payment/checkmo/title")
CHECK_PAYABLE=$(get_config "payment/checkmo/payable_to")
CHECK_ADDRESS=$(get_config "payment/checkmo/mailing_address")
CHECK_SORT=$(get_config "payment/checkmo/sort_order")

# Escape special characters for JSON (especially newlines in instructions/address)
# Python's json.dumps via a quick python one-liner is safer than sed for multiline strings
export BANK_INSTRUCTIONS
export CHECK_ADDRESS

clean_json_string() {
    python3 -c "import os, json; print(json.dumps(os.environ.get('$1', '')))"
}

BANK_INSTRUCTIONS_JSON=$(clean_json_string "BANK_INSTRUCTIONS")
CHECK_ADDRESS_JSON=$(clean_json_string "CHECK_ADDRESS")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/payment_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "bank_transfer": {
        "active": "${BANK_ACTIVE:-0}",
        "title": "${BANK_TITLE:-}",
        "instructions_raw": $BANK_INSTRUCTIONS_JSON,
        "sort_order": "${BANK_SORT:-}"
    },
    "check_money_order": {
        "active": "${CHECK_ACTIVE:-0}",
        "title": "${CHECK_TITLE:-}",
        "payable_to": "${CHECK_PAYABLE:-}",
        "mailing_address_raw": $CHECK_ADDRESS_JSON,
        "sort_order": "${CHECK_SORT:-}"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
safe_write_json "$TEMP_JSON" /tmp/payment_config_result.json

echo "Exported configuration:"
cat /tmp/payment_config_result.json
echo ""
echo "=== Export Complete ==="
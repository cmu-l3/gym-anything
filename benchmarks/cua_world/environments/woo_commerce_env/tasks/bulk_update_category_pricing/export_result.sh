#!/bin/bash
echo "=== Exporting Bulk Update Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_end_time.txt

# Verify DB connection
if ! check_db_connection; then
    echo "Error: DB unreachable" > /tmp/task_result.json
    exit 1
fi

# ==============================================================================
# CAPTURE FINAL STATE
# ==============================================================================

# Helper to get price by exact name
get_price() {
    local name="$1"
    local p
    p=$(wc_query "SELECT meta_value FROM wp_postmeta pm JOIN wp_posts p ON pm.post_id = p.ID WHERE p.post_title='$name' AND pm.meta_key='_regular_price' LIMIT 1")
    echo "${p:-0}"
}

# Capture current prices of target and control items
T_SHIRT_PRICE=$(get_price "Organic Cotton T-Shirt")
JEANS_PRICE=$(get_price "Slim Fit Denim Jeans")
SWEATER_PRICE=$(get_price "Merino Wool Sweater")
HEADPHONES_PRICE=$(get_price "Wireless Bluetooth Headphones")
CHARGER_PRICE=$(get_price "USB-C Laptop Charger 65W")

# Load initial prices for comparison in verifier (passed via json structure)
INITIAL_JSON=$(cat /tmp/initial_prices.json 2>/dev/null || echo "{}")

# Construct result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "initial_state": $INITIAL_JSON,
  "final_state": {
    "clothing": {
      "Organic Cotton T-Shirt": $T_SHIRT_PRICE,
      "Slim Fit Denim Jeans": $JEANS_PRICE,
      "Merino Wool Sweater": $SWEATER_PRICE
    },
    "electronics": {
      "Wireless Bluetooth Headphones": $HEADPHONES_PRICE,
      "USB-C Laptop Charger 65W": $CHARGER_PRICE
    }
  },
  "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "Export complete. Result:"
cat /tmp/task_result.json
#!/bin/bash
# Export script for Shipping Configuration task

echo "=== Exporting Shipping Configuration Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Helper function to get config value
get_config_value() {
    local path="$1"
    # Query core_config_data for default scope (scope_id=0)
    # We use explicit SQL to avoid caching issues with bin/magento config:show
    local val=$(magento_query "SELECT value FROM core_config_data WHERE path='$path' AND scope='default' AND scope_id=0" 2>/dev/null | tail -1)
    echo "$val"
}

# 1. Gather Shipping Origin Settings
ORIGIN_COUNTRY=$(get_config_value "shipping/origin/country_id")
ORIGIN_REGION_ID=$(get_config_value "shipping/origin/region_id")
ORIGIN_POSTCODE=$(get_config_value "shipping/origin/postcode")
ORIGIN_CITY=$(get_config_value "shipping/origin/city")
ORIGIN_STREET=$(get_config_value "shipping/origin/street_line1")

# 2. Gather Flat Rate Settings
FLATRATE_ACTIVE=$(get_config_value "carriers/flatrate/active")
FLATRATE_TITLE=$(get_config_value "carriers/flatrate/title")
FLATRATE_NAME=$(get_config_value "carriers/flatrate/name")
FLATRATE_PRICE=$(get_config_value "carriers/flatrate/price")
FLATRATE_TYPE=$(get_config_value "carriers/flatrate/type")
FLATRATE_SORT=$(get_config_value "carriers/flatrate/sort_order")

# 3. Gather Free Shipping Settings
FREESHIP_ACTIVE=$(get_config_value "carriers/freeshipping/active")
FREESHIP_SUBTOTAL=$(get_config_value "carriers/freeshipping/free_shipping_subtotal")
FREESHIP_SORT=$(get_config_value "carriers/freeshipping/sort_order")

echo "Debug Values:"
echo "Origin: $ORIGIN_COUNTRY, $ORIGIN_REGION_ID, $ORIGIN_POSTCODE, $ORIGIN_CITY"
echo "Flatrate: $FLATRATE_ACTIVE, $FLATRATE_PRICE, $FLATRATE_TITLE"
echo "Freeship: $FREESHIP_ACTIVE, $FREESHIP_SUBTOTAL"

# Escape strings for JSON
ORIGIN_CITY_ESC=$(echo "$ORIGIN_CITY" | sed 's/"/\\"/g')
ORIGIN_STREET_ESC=$(echo "$ORIGIN_STREET" | sed 's/"/\\"/g')
FLATRATE_TITLE_ESC=$(echo "$FLATRATE_TITLE" | sed 's/"/\\"/g')
FLATRATE_NAME_ESC=$(echo "$FLATRATE_NAME" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/shipping_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "origin": {
        "country_id": "${ORIGIN_COUNTRY:-}",
        "region_id": "${ORIGIN_REGION_ID:-}",
        "postcode": "${ORIGIN_POSTCODE:-}",
        "city": "$ORIGIN_CITY_ESC",
        "street_line1": "$ORIGIN_STREET_ESC"
    },
    "flatrate": {
        "active": "${FLATRATE_ACTIVE:-0}",
        "title": "$FLATRATE_TITLE_ESC",
        "name": "$FLATRATE_NAME_ESC",
        "price": "${FLATRATE_PRICE:-0}",
        "type": "${FLATRATE_TYPE:-}",
        "sort_order": "${FLATRATE_SORT:-}"
    },
    "freeshipping": {
        "active": "${FREESHIP_ACTIVE:-0}",
        "subtotal": "${FREESHIP_SUBTOTAL:-0}",
        "sort_order": "${FREESHIP_SORT:-}"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/shipping_result.json

echo ""
cat /tmp/shipping_result.json
echo ""
echo "=== Export Complete ==="
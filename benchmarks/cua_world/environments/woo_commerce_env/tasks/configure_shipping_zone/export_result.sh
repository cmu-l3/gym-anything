#!/bin/bash
# Export script for Configure Shipping Zone task
set -e

echo "=== Exporting Configure Shipping Zone Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check if a zone named "Continental US" exists
ZONE_INFO=$(wc_query "SELECT zone_id, zone_name FROM wp_woocommerce_shipping_zones WHERE LOWER(TRIM(zone_name)) = 'continental us' LIMIT 1" 2>/dev/null)
ZONE_FOUND="false"
ZONE_ID=""
ZONE_NAME=""

if [ -n "$ZONE_INFO" ]; then
    ZONE_FOUND="true"
    ZONE_ID=$(echo "$ZONE_INFO" | cut -f1)
    ZONE_NAME=$(echo "$ZONE_INFO" | cut -f2)
fi

# 2. Check if the region is "US" (United States)
REGION_FOUND="false"
REGION_CODE=""

if [ "$ZONE_FOUND" = "true" ]; then
    REGION_DATA=$(wc_query "SELECT location_code FROM wp_woocommerce_shipping_zone_locations WHERE zone_id = $ZONE_ID AND location_type = 'country' AND location_code = 'US' LIMIT 1" 2>/dev/null)
    if [ -n "$REGION_DATA" ]; then
        REGION_FOUND="true"
        REGION_CODE="$REGION_DATA"
    fi
fi

# 3. Check for Flat Rate method
METHOD_FOUND="false"
METHOD_ENABLED="false"
INSTANCE_ID=""
METHOD_ID=""

if [ "$ZONE_FOUND" = "true" ]; then
    METHOD_DATA=$(wc_query "SELECT instance_id, method_id, is_enabled FROM wp_woocommerce_shipping_zone_methods WHERE zone_id = $ZONE_ID AND method_id = 'flat_rate' LIMIT 1" 2>/dev/null)
    if [ -n "$METHOD_DATA" ]; then
        METHOD_FOUND="true"
        INSTANCE_ID=$(echo "$METHOD_DATA" | cut -f1)
        METHOD_ID=$(echo "$METHOD_DATA" | cut -f2)
        IS_ENABLED=$(echo "$METHOD_DATA" | cut -f3)
        if [ "$IS_ENABLED" = "1" ]; then
            METHOD_ENABLED="true"
        fi
    fi
fi

# 4. Check Cost (Stored in wp_options as serialized array)
# Option name format: woocommerce_flat_rate_{instance_id}_settings
COST_VALUE=""
COST_FOUND="false"

if [ "$METHOD_FOUND" = "true" ] && [ -n "$INSTANCE_ID" ]; then
    OPTION_NAME="woocommerce_flat_rate_${INSTANCE_ID}_settings"
    
    # Use WP-CLI to get the option as JSON, then parse with Python
    # This is much safer than parsing serialized PHP in bash
    COST_VALUE=$(cd /var/www/html/wordpress && wp option get "$OPTION_NAME" --format=json --allow-root 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('cost', ''))" 2>/dev/null || echo "")
    
    if [ -n "$COST_VALUE" ]; then
        COST_FOUND="true"
    fi
fi

# Count total zones created during task (Anti-gaming)
INITIAL_COUNT=$(cat /tmp/initial_zone_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_woocommerce_shipping_zones" 2>/dev/null || echo "0")
NEW_ZONES_CREATED=$((CURRENT_COUNT - INITIAL_COUNT))

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "zone_found": $ZONE_FOUND,
    "zone_name": "$(json_escape "$ZONE_NAME")",
    "region_correct": $REGION_FOUND,
    "method_found": $METHOD_FOUND,
    "method_enabled": $METHOD_ENABLED,
    "cost_found": $COST_FOUND,
    "cost_value": "$(json_escape "$COST_VALUE")",
    "new_zones_created": $NEW_ZONES_CREATED,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json
cat /tmp/task_result.json

echo "=== Export Complete ==="
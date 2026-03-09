#!/bin/bash
# Export script for Configure Formula Shipping Rate task
set -e
echo "=== Exporting Configure Formula Shipping Rate Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve the Zone ID we created in setup
ZONE_ID=$(cat /tmp/target_zone_id.txt 2>/dev/null || wc_query "SELECT zone_id FROM wp_woocommerce_shipping_zones WHERE zone_name='Domestic' LIMIT 1")

RESULT_JSON_PATH="/tmp/task_result.json"

if [ -z "$ZONE_ID" ]; then
    echo "FAIL: 'Domestic' shipping zone not found."
    cat > "$RESULT_JSON_PATH" << EOF
{
    "zone_found": false,
    "methods": [],
    "error": "Domestic zone missing"
}
EOF
    exit 0
fi

echo "Checking methods in Zone ID: $ZONE_ID..."

# Get all methods in this zone
# returns: method_id, instance_id
# We specifically look for 'flat_rate'
METHODS_RAW=$(wc_query "SELECT instance_id FROM wp_woocommerce_shipping_zone_methods WHERE zone_id=$ZONE_ID AND method_id='flat_rate'")

# Initialize JSON array for methods
METHODS_JSON="[]"

if [ -n "$METHODS_RAW" ]; then
    METHODS_JSON="["
    FIRST=true
    
    for INSTANCE_ID in $METHODS_RAW; do
        echo "Processing Flat Rate Instance ID: $INSTANCE_ID"
        
        # Retrieve settings from wp_options using WP-CLI (handles serialization)
        # Option name: woocommerce_flat_rate_{instance_id}_settings
        SETTINGS_RAW=$(wp option get "woocommerce_flat_rate_${INSTANCE_ID}_settings" --format=json --user=admin --allow-root 2>/dev/null || echo "{}")
        
        # Extract fields using jq
        TITLE=$(echo "$SETTINGS_RAW" | jq -r '.title // empty')
        COST=$(echo "$SETTINGS_RAW" | jq -r '.cost // empty')
        TAX_STATUS=$(echo "$SETTINGS_RAW" | jq -r '.tax_status // empty')
        
        # Escape for JSON embedding
        TITLE_ESC=$(json_escape "$TITLE")
        COST_ESC=$(json_escape "$COST")
        
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            METHODS_JSON="$METHODS_JSON,"
        fi
        
        METHODS_JSON="$METHODS_JSON {
            \"instance_id\": $INSTANCE_ID,
            \"title\": \"$TITLE_ESC\",
            \"cost\": \"$COST_ESC\",
            \"tax_status\": \"$TAX_STATUS\"
        }"
    done
    METHODS_JSON="$METHODS_JSON]"
fi

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "zone_found": true,
    "zone_id": $ZONE_ID,
    "methods": $METHODS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move safely
safe_write_json "$TEMP_JSON" "$RESULT_JSON_PATH"

echo "Exported Data:"
cat "$RESULT_JSON_PATH"
echo ""
echo "=== Export Complete ==="
#!/bin/bash
# Export script for Configure Shipping Classes task

echo "=== Exporting Configure Shipping Classes Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get verification data
INSTANCE_ID=$(cat /tmp/shipping_method_instance_id.txt 2>/dev/null || echo "1")
INITIAL_MAX_TERM_ID=$(cat /tmp/initial_max_term_id.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Checking shipping classes..."

# Function to get shipping class info by slug
get_class_info() {
    local slug="$1"
    # Returns: term_id | name | slug | count
    wc_query "SELECT t.term_id, t.name, t.slug, tt.count 
              FROM wp_terms t 
              JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id 
              WHERE tt.taxonomy = 'product_shipping_class' 
              AND t.slug = '$slug' LIMIT 1"
}

# Check "Bulky Items" class
BULKY_INFO=$(get_class_info "bulky-items")
BULKY_FOUND="false"
BULKY_ID=""
if [ -n "$BULKY_INFO" ]; then
    BULKY_FOUND="true"
    BULKY_ID=$(echo "$BULKY_INFO" | cut -f1)
fi

# Check "Fragile" class
FRAGILE_INFO=$(get_class_info "fragile")
FRAGILE_FOUND="false"
FRAGILE_ID=""
if [ -n "$FRAGILE_INFO" ]; then
    FRAGILE_FOUND="true"
    FRAGILE_ID=$(echo "$FRAGILE_INFO" | cut -f1)
fi

echo "Bulky Items Found: $BULKY_FOUND (ID: $BULKY_ID)"
echo "Fragile Found: $FRAGILE_FOUND (ID: $FRAGILE_ID)"

# 3. Check Flat Rate Settings (Costs)
echo "Checking shipping costs..."
OPTION_NAME="woocommerce_flat_rate_${INSTANCE_ID}_settings"
# Get option value as JSON
SETTINGS_JSON=$(wp option get "$OPTION_NAME" --format=json --allow-root 2>/dev/null || echo "{}")

# 4. Check Product Assignments
echo "Checking product assignments..."

# Helper to check if product has term
check_product_term() {
    local sku="$1"
    local term_id="$2"
    if [ -z "$term_id" ]; then echo "false"; return; fi
    
    local prod_id=$(get_product_by_sku "$sku" | cut -f1)
    if [ -z "$prod_id" ]; then echo "false"; return; fi

    local count=$(wc_query "SELECT COUNT(*) FROM wp_term_relationships WHERE object_id=$prod_id AND term_taxonomy_id=(SELECT term_taxonomy_id FROM wp_term_taxonomy WHERE term_id=$term_id)")
    if [ "$count" -gt "0" ]; then echo "true"; else echo "false"; fi
}

ASSIGNED_BULKY=$(check_product_term "MWS-GRY-L" "$BULKY_ID")
ASSIGNED_FRAGILE=$(check_product_term "WBH-001" "$FRAGILE_ID")

echo "Sweater assigned Bulky: $ASSIGNED_BULKY"
echo "Headphones assigned Fragile: $ASSIGNED_FRAGILE"

# 5. Anti-gaming: Check if terms are new
TERMS_ARE_NEW="false"
if [ -n "$BULKY_ID" ] && [ -n "$FRAGILE_ID" ]; then
    if [ "$BULKY_ID" -gt "$INITIAL_MAX_TERM_ID" ] && [ "$FRAGILE_ID" -gt "$INITIAL_MAX_TERM_ID" ]; then
        TERMS_ARE_NEW="true"
    fi
fi

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "bulky_class": {
        "found": $BULKY_FOUND,
        "id": "${BULKY_ID:-null}",
        "slug": "bulky-items"
    },
    "fragile_class": {
        "found": $FRAGILE_FOUND,
        "id": "${FRAGILE_ID:-null}",
        "slug": "fragile"
    },
    "flat_rate_settings": $SETTINGS_JSON,
    "assignments": {
        "sweater_bulky": $ASSIGNED_BULKY,
        "headphones_fragile": $ASSIGNED_FRAGILE
    },
    "meta": {
        "terms_are_new": $TERMS_ARE_NEW,
        "instance_id": "$INSTANCE_ID",
        "task_start": $TASK_START_TIME,
        "export_time": $(date +%s)
    }
}
EOF

# Move to final location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="
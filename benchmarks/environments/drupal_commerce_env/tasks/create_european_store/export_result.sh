#!/bin/bash
# Export script for Create European Store task
echo "=== Exporting Create European Store Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definition if utils not loaded
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
    json_escape() {
        echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n' | tr -d '\r'
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get baseline data
INITIAL_MAX_ID=$(cat /tmp/max_store_id 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Find the new store (ID > INITIAL_MAX_ID and name match)
# We search broadly first
NEW_STORE_ID=""
STORE_NAME=""
STORE_MAIL=""
STORE_CURRENCY=""
STORE_IS_DEFAULT=""
STORE_STATUS=""

# Try to find store by expected name first
STORE_DATA=$(drupal_db_query "SELECT store_id, name, mail, default_currency, is_default, status FROM commerce_store_field_data WHERE name LIKE '%Urban Electronics Europe%' ORDER BY store_id DESC LIMIT 1")

if [ -n "$STORE_DATA" ]; then
    NEW_STORE_ID=$(echo "$STORE_DATA" | cut -f1)
    STORE_NAME=$(echo "$STORE_DATA" | cut -f2)
    STORE_MAIL=$(echo "$STORE_DATA" | cut -f3)
    STORE_CURRENCY=$(echo "$STORE_DATA" | cut -f4)
    STORE_IS_DEFAULT=$(echo "$STORE_DATA" | cut -f5)
    STORE_STATUS=$(echo "$STORE_DATA" | cut -f6)
else
    # Fallback: check any new store created
    STORE_DATA=$(drupal_db_query "SELECT store_id, name, mail, default_currency, is_default, status FROM commerce_store_field_data WHERE store_id > $INITIAL_MAX_ID ORDER BY store_id DESC LIMIT 1")
    if [ -n "$STORE_DATA" ]; then
        NEW_STORE_ID=$(echo "$STORE_DATA" | cut -f1)
        STORE_NAME=$(echo "$STORE_DATA" | cut -f2)
        STORE_MAIL=$(echo "$STORE_DATA" | cut -f3)
        STORE_CURRENCY=$(echo "$STORE_DATA" | cut -f4)
        STORE_IS_DEFAULT=$(echo "$STORE_DATA" | cut -f5)
        STORE_STATUS=$(echo "$STORE_DATA" | cut -f6)
    fi
fi

# 2. Check Address if store found
ADDRESS_COUNTRY=""
ADDRESS_LOCALITY=""
if [ -n "$NEW_STORE_ID" ]; then
    ADDR_DATA=$(drupal_db_query "SELECT address_country_code, address_locality FROM commerce_store__address WHERE entity_id = $NEW_STORE_ID")
    if [ -n "$ADDR_DATA" ]; then
        ADDRESS_COUNTRY=$(echo "$ADDR_DATA" | cut -f1)
        ADDRESS_LOCALITY=$(echo "$ADDR_DATA" | cut -f2)
    fi
fi

# 3. Check Product Assignments
# We check the 3 specific products requested
# Return status: 0=not assigned to new store, 1=assigned to new store
# Also check if they remain in old store (store_id=1, usually)

check_product_assignment() {
    local title="$1"
    local target_store_id="$2"
    
    # Get product ID
    local pid=$(drupal_db_query "SELECT product_id FROM commerce_product_field_data WHERE title LIKE '%$title%' LIMIT 1")
    
    if [ -z "$pid" ]; then
        echo "0:0" # Product not found
        return
    fi
    
    # Check assignment to target store
    local assigned_new=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__stores WHERE entity_id = $pid AND stores_target_id = $target_store_id")
    
    # Check assignment to original store (assuming ID 1)
    local assigned_old=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__stores WHERE entity_id = $pid AND stores_target_id = 1")
    
    echo "${assigned_new:-0}:${assigned_old:-0}"
}

SONY_ASSIGNMENT="0:0"
SAMSUNG_ASSIGNMENT="0:0"
LOGI_ASSIGNMENT="0:0"

if [ -n "$NEW_STORE_ID" ]; then
    SONY_ASSIGNMENT=$(check_product_assignment "Sony WH-1000XM5" "$NEW_STORE_ID")
    SAMSUNG_ASSIGNMENT=$(check_product_assignment "Samsung Galaxy S24 Ultra" "$NEW_STORE_ID")
    LOGI_ASSIGNMENT=$(check_product_assignment "Logitech MX Master 3S" "$NEW_STORE_ID")
fi

# Create JSON result
cat > /tmp/european_store_result.json << EOF
{
    "store_found": $([ -n "$NEW_STORE_ID" ] && echo "true" || echo "false"),
    "store_id": ${NEW_STORE_ID:-0},
    "is_new_id": $([ "${NEW_STORE_ID:-0}" -gt "$INITIAL_MAX_ID" ] && echo "true" || echo "false"),
    "store_name": "$(json_escape "$STORE_NAME")",
    "store_mail": "$(json_escape "$STORE_MAIL")",
    "store_currency": "$(json_escape "$STORE_CURRENCY")",
    "is_default": ${STORE_IS_DEFAULT:-0},
    "status": ${STORE_STATUS:-0},
    "address_country": "$(json_escape "$ADDRESS_COUNTRY")",
    "address_locality": "$(json_escape "$ADDRESS_LOCALITY")",
    "sony_assigned_new": $(echo "$SONY_ASSIGNMENT" | cut -d: -f1),
    "sony_assigned_old": $(echo "$SONY_ASSIGNMENT" | cut -d: -f2),
    "samsung_assigned_new": $(echo "$SAMSUNG_ASSIGNMENT" | cut -d: -f1),
    "samsung_assigned_old": $(echo "$SAMSUNG_ASSIGNMENT" | cut -d: -f2),
    "logi_assigned_new": $(echo "$LOGI_ASSIGNMENT" | cut -d: -f1),
    "logi_assigned_old": $(echo "$LOGI_ASSIGNMENT" | cut -d: -f2)
}
EOF

echo "Export complete. Result file:"
cat /tmp/european_store_result.json
#!/bin/bash
# Export script for Separate Catalog Store Setup task

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Verify Root Category "Pro Catalog"
# Must look for category with name 'Pro Catalog' that is Level 1 (Root)
# Note: Level 0 is absolute root, Level 1 is a Catalog Root, Level 2 is top-level category
echo "Checking Root Category..."
ROOT_CAT_DATA=$(magento_query "
SELECT e.entity_id, e.parent_id, e.level 
FROM catalog_category_entity e
JOIN catalog_category_entity_varchar v ON e.entity_id = v.entity_id
WHERE v.attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3)
AND v.value = 'Pro Catalog'
ORDER BY e.entity_id DESC LIMIT 1
" 2>/dev/null | tail -1)

ROOT_ID=$(echo "$ROOT_CAT_DATA" | awk '{print $1}')
ROOT_PARENT=$(echo "$ROOT_CAT_DATA" | awk '{print $2}')
ROOT_LEVEL=$(echo "$ROOT_CAT_DATA" | awk '{print $3}')

# 2. Verify Subcategory "Office Solutions"
echo "Checking Subcategory..."
SUB_CAT_DATA=$(magento_query "
SELECT e.entity_id, e.parent_id 
FROM catalog_category_entity e
JOIN catalog_category_entity_varchar v ON e.entity_id = v.entity_id
WHERE v.attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3)
AND v.value = 'Office Solutions'
ORDER BY e.entity_id DESC LIMIT 1
" 2>/dev/null | tail -1)

SUB_ID=$(echo "$SUB_CAT_DATA" | awk '{print $1}')
SUB_PARENT=$(echo "$SUB_CAT_DATA" | awk '{print $2}')

# 3. Verify Store Group "NestWell Pro"
echo "Checking Store Group..."
STORE_GROUP_DATA=$(magento_query "
SELECT group_id, root_category_id 
FROM store_group 
WHERE name = 'NestWell Pro' 
LIMIT 1
" 2>/dev/null | tail -1)

GROUP_ID=$(echo "$STORE_GROUP_DATA" | awk '{print $1}')
GROUP_ROOT_ID=$(echo "$STORE_GROUP_DATA" | awk '{print $2}')

# 4. Verify Store View "Pro English"
echo "Checking Store View..."
STORE_VIEW_DATA=$(magento_query "
SELECT store_id, group_id, is_active 
FROM store 
WHERE code = 'pro_en' 
LIMIT 1
" 2>/dev/null | tail -1)

VIEW_ID=$(echo "$STORE_VIEW_DATA" | awk '{print $1}')
VIEW_GROUP_ID=$(echo "$STORE_VIEW_DATA" | awk '{print $2}')
VIEW_ACTIVE=$(echo "$STORE_VIEW_DATA" | awk '{print $3}')

# 5. Verify Product Assignment
# Check if LAPTOP-001 is assigned to Office Solutions category
echo "Checking Product Assignment..."
PRODUCT_ASSIGNED="false"
if [ -n "$SUB_ID" ]; then
    LAPTOP_ID=$(get_product_by_sku "LAPTOP-001" | cut -f1)
    if [ -n "$LAPTOP_ID" ]; then
        LINK_CHECK=$(magento_query "SELECT COUNT(*) FROM catalog_category_product WHERE category_id=$SUB_ID AND product_id=$LAPTOP_ID" 2>/dev/null | tail -1)
        if [ "$LINK_CHECK" -gt "0" ]; then
            PRODUCT_ASSIGNED="true"
        fi
    fi
fi

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "root_category": {
        "id": "${ROOT_ID:-0}",
        "parent_id": "${ROOT_PARENT:-0}",
        "level": "${ROOT_LEVEL:-0}"
    },
    "subcategory": {
        "id": "${SUB_ID:-0}",
        "parent_id": "${SUB_PARENT:-0}"
    },
    "store_group": {
        "id": "${GROUP_ID:-0}",
        "root_category_id": "${GROUP_ROOT_ID:-0}"
    },
    "store_view": {
        "id": "${VIEW_ID:-0}",
        "group_id": "${VIEW_GROUP_ID:-0}",
        "is_active": "${VIEW_ACTIVE:-0}"
    },
    "product_assigned": $PRODUCT_ASSIGNED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json
cat /tmp/task_result.json
echo "=== Export Complete ==="
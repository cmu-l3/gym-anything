#!/bin/bash
# Export script for Add Category task

echo "=== Exporting Add Category Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current category count
CURRENT_COUNT=$(get_category_count 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_category_count 2>/dev/null || echo "0")

echo "Category count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent categories
echo ""
echo "=== DEBUG: Most recent categories in database ==="
magento_query_headers "SELECT e.entity_id, v.value as name, e.parent_id, e.level
    FROM catalog_category_entity e
    JOIN catalog_category_entity_varchar v ON e.entity_id = v.entity_id
    WHERE v.attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3)
    AND v.store_id = 0
    ORDER BY e.entity_id DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check for the target category by name (case-insensitive)
echo "Checking for category 'Eco-Friendly' (case-insensitive)..."
CATEGORY_DATA=$(get_category_by_name "Eco-Friendly" 2>/dev/null)

# No fallback logic - we only accept the exact expected category name
if [ -z "$CATEGORY_DATA" ]; then
    echo "Category 'Eco-Friendly' NOT found in database"
fi

# Parse category data
CATEGORY_FOUND="false"
CATEGORY_ID=""
CATEGORY_NAME=""
CATEGORY_PARENT_ID=""
CATEGORY_LEVEL=""
CATEGORY_IS_ACTIVE=""
CATEGORY_INCLUDE_IN_MENU=""

if [ -n "$CATEGORY_DATA" ]; then
    CATEGORY_FOUND="true"
    CATEGORY_ID=$(echo "$CATEGORY_DATA" | cut -f1)
    CATEGORY_NAME=$(echo "$CATEGORY_DATA" | cut -f2)
    CATEGORY_PARENT_ID=$(echo "$CATEGORY_DATA" | cut -f3)
    CATEGORY_LEVEL=$(echo "$CATEGORY_DATA" | cut -f4)

    # Get is_active attribute
    CATEGORY_IS_ACTIVE=$(magento_query "SELECT value FROM catalog_category_entity_int
        WHERE entity_id=$CATEGORY_ID
        AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='is_active' AND entity_type_id=3)
        AND store_id=0 LIMIT 1" 2>/dev/null)

    # Get include_in_menu attribute
    CATEGORY_INCLUDE_IN_MENU=$(magento_query "SELECT value FROM catalog_category_entity_int
        WHERE entity_id=$CATEGORY_ID
        AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='include_in_menu' AND entity_type_id=3)
        AND store_id=0 LIMIT 1" 2>/dev/null)

    echo "Category found: ID=$CATEGORY_ID, Name='$CATEGORY_NAME', Parent=$CATEGORY_PARENT_ID, Level=$CATEGORY_LEVEL, Active=$CATEGORY_IS_ACTIVE, InMenu=$CATEGORY_INCLUDE_IN_MENU"
else
    echo "Category 'Eco-Friendly' NOT found in database"
fi

# Escape special characters for JSON
CATEGORY_NAME_ESC=$(echo "$CATEGORY_NAME" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/add_category_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_category_count": ${INITIAL_COUNT:-0},
    "current_category_count": ${CURRENT_COUNT:-0},
    "category_found": $CATEGORY_FOUND,
    "category": {
        "id": "$CATEGORY_ID",
        "name": "$CATEGORY_NAME_ESC",
        "parent_id": "$CATEGORY_PARENT_ID",
        "level": "$CATEGORY_LEVEL",
        "is_active": "$CATEGORY_IS_ACTIVE",
        "include_in_menu": "$CATEGORY_INCLUDE_IN_MENU"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/add_category_result.json

echo ""
cat /tmp/add_category_result.json
echo ""
echo "=== Export Complete ==="

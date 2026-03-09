#!/bin/bash
# Export script for implement_shoppable_editorial_content
echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Helper for DB queries
db_query() {
    docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
}

# 1. CHECK CONTENT TYPE
# Config name: node.type.editorial_review
CONTENT_TYPE_EXISTS=$(db_query "SELECT COUNT(*) FROM config WHERE name = 'node.type.editorial_review'")
echo "Content type exists: $CONTENT_TYPE_EXISTS"

# 2. CHECK FIELD CONFIGURATION
# Config name: field.field.node.editorial_review.field_merchandise
# We check the serialized data to ensure it is an entity reference to commerce_product
FIELD_CONFIG_DATA=$(db_query "SELECT data FROM config WHERE name = 'field.field.node.editorial_review.field_merchandise'")
FIELD_STORAGE_DATA=$(db_query "SELECT data FROM config WHERE name = 'field.storage.node.field_merchandise'")

FIELD_EXISTS="false"
FIELD_TYPE_CORRECT="false"
TARGET_TYPE_CORRECT="false"

if [ -n "$FIELD_CONFIG_DATA" ]; then
    FIELD_EXISTS="true"
    # Check storage for type 'entity_reference'
    if echo "$FIELD_STORAGE_DATA" | grep -q "entity_reference"; then
        FIELD_TYPE_CORRECT="true"
    fi
    # Check config for target 'commerce_product'
    if echo "$FIELD_CONFIG_DATA" | grep -q "commerce_product"; then
        TARGET_TYPE_CORRECT="true"
    fi
fi

# 3. CHECK DISPLAY CONFIGURATION
# Config name: core.entity_view_display.node.editorial_review.default
DISPLAY_CONFIG=$(db_query "SELECT data FROM config WHERE name = 'core.entity_view_display.node.editorial_review.default'")

DISPLAY_FORMATTER=""
DISPLAY_VIEW_MODE=""
FIELD_IN_DISPLAY="false"

if [ -n "$DISPLAY_CONFIG" ]; then
    # We use python to parse the PHP serialized string or JSON if we can extract it.
    # Since it's serialized PHP in the DB, simple grep is safer for shell.
    
    # Check if field_merchandise is in the content component
    if echo "$DISPLAY_CONFIG" | grep -q "field_merchandise"; then
        FIELD_IN_DISPLAY="true"
        
        # Check formatter type (entity_reference_entity_view = "Rendered entity")
        if echo "$DISPLAY_CONFIG" | grep -q "entity_reference_entity_view"; then
            DISPLAY_FORMATTER="entity_reference_entity_view"
        elif echo "$DISPLAY_CONFIG" | grep -q "entity_reference_label"; then
            DISPLAY_FORMATTER="entity_reference_label"
        elif echo "$DISPLAY_CONFIG" | grep -q "entity_reference_entity_id"; then
            DISPLAY_FORMATTER="entity_reference_entity_id"
        fi
        
        # Check view mode setting (s:9:"view_mode";s:6:"teaser";)
        # Grep pattern loosely
        if echo "$DISPLAY_CONFIG" | grep -q "view_mode.*teaser"; then
            DISPLAY_VIEW_MODE="teaser"
        elif echo "$DISPLAY_CONFIG" | grep -q "view_mode.*default"; then
            DISPLAY_VIEW_MODE="default"
        fi
    fi
fi

# 4. CHECK CREATED CONTENT
# Find a node of type editorial_review
NODE_ID=$(db_query "SELECT nid FROM node_field_data WHERE type = 'editorial_review' ORDER BY nid DESC LIMIT 1")
NODE_TITLE=""
NODE_STATUS=""
REFERENCED_PRODUCT_ID=""

if [ -n "$NODE_ID" ]; then
    NODE_TITLE=$(db_query "SELECT title FROM node_field_data WHERE nid = $NODE_ID")
    NODE_STATUS=$(db_query "SELECT status FROM node_field_data WHERE nid = $NODE_ID")
    
    # Check the field table for reference
    # Table name is typically node__field_merchandise
    REFERENCED_PRODUCT_ID=$(db_query "SELECT field_merchandise_target_id FROM node__field_merchandise WHERE entity_id = $NODE_ID")
fi

REFERENCED_PRODUCT_CORRECT="false"
if [ -n "$REFERENCED_PRODUCT_ID" ]; then
    # Verify the product is the Sony one
    PROD_TITLE=$(db_query "SELECT title FROM commerce_product_field_data WHERE product_id = $REFERENCED_PRODUCT_ID")
    if echo "$PROD_TITLE" | grep -iq "Sony"; then
        REFERENCED_PRODUCT_CORRECT="true"
    fi
fi

# Export to JSON
create_result_json /tmp/task_result.json \
    "content_type_exists=$CONTENT_TYPE_EXISTS" \
    "field_exists=$FIELD_EXISTS" \
    "field_type_correct=$FIELD_TYPE_CORRECT" \
    "target_type_correct=$TARGET_TYPE_CORRECT" \
    "field_in_display=$FIELD_IN_DISPLAY" \
    "display_formatter=$DISPLAY_FORMATTER" \
    "display_view_mode=$DISPLAY_VIEW_MODE" \
    "node_created=$( [ -n "$NODE_ID" ] && echo "true" || echo "false" )" \
    "node_title=$(json_escape "$NODE_TITLE")" \
    "node_status=$NODE_STATUS" \
    "referenced_product_correct=$REFERENCED_PRODUCT_CORRECT"

chmod 666 /tmp/task_result.json

echo "Export complete. JSON content:"
cat /tmp/task_result.json
#!/bin/bash
# Export script for create_visual_category_navigation
echo "=== Exporting Visual Category Navigation Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Configuration: Field Existence
# Check for field storage config
FIELD_STORAGE_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.storage.taxonomy_term.field_category_image'")
# Check for field instance config on the specific vocabulary
FIELD_INSTANCE_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.field.taxonomy_term.product_categories.field_category_image'")

# 3. Query Data: Image Assignments
# We check the dedicated table for the field: taxonomy_term__field_category_image
# Columns: entity_id (term_id), field_category_image_target_id (file_id)

# Helper to get term ID by name
get_tid() {
    drupal_db_query "SELECT tid FROM taxonomy_term_field_data WHERE vid='product_categories' AND name='$1' LIMIT 1"
}

HEADPHONES_TID=$(get_tid "Headphones")
KEYBOARDS_TID=$(get_tid "Keyboards")
MONITORS_TID=$(get_tid "Monitors")

check_image_assigned() {
    local tid=$1
    if [ -z "$tid" ]; then echo "false"; return; fi
    
    local fid=$(drupal_db_query "SELECT field_category_image_target_id FROM taxonomy_term__field_category_image WHERE entity_id=$tid LIMIT 1")
    if [ -n "$fid" ] && [ "$fid" != "NULL" ]; then
        echo "true"
    else
        echo "false"
    fi
}

HEADPHONES_HAS_IMAGE=$(check_image_assigned "$HEADPHONES_TID")
KEYBOARDS_HAS_IMAGE=$(check_image_assigned "$KEYBOARDS_TID")
MONITORS_HAS_IMAGE=$(check_image_assigned "$MONITORS_TID")

# 4. Query Configuration: View Existence
VIEW_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'views.view.category_grid'")

# Get View Config Data (BLOB) to check specific settings if possible, or use Drush
# Using Drush to export config is reliable
mkdir -p /tmp/config_export
drush_cmd config:export --destination=/tmp/config_export -y > /dev/null 2>&1

VIEW_CONFIG_FILE="/tmp/config_export/views.view.category_grid.yml"
IS_GRID="false"
SHOWS_TERMS="false"
HAS_IMAGE_FIELD="false"

if [ -f "$VIEW_CONFIG_FILE" ]; then
    # Simple grep checks on the YAML
    if grep -q "style_plugin: grid" "$VIEW_CONFIG_FILE"; then IS_GRID="true"; fi
    if grep -q "base_table: taxonomy_term_field_data" "$VIEW_CONFIG_FILE"; then SHOWS_TERMS="true"; fi
    if grep -q "field_category_image" "$VIEW_CONFIG_FILE"; then HAS_IMAGE_FIELD="true"; fi
fi

# 5. Query Configuration: Block Placement
# Blocks are config entities: block.block.[theme]_[id]
# We look for a block that uses the view plugin
BLOCK_PLACED=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name LIKE 'block.block.%' AND data LIKE '%plugin: \'views_block:category_grid%'")

# Also check if it's in the content region (requires parsing the config blob or YML)
# We'll rely on the count > 0 for placement, and maybe grep the export for region
BLOCK_IN_CONTENT="false"
if [ "$BLOCK_PLACED" -gt 0 ]; then
    # Find the specific block file
    BLOCK_FILE=$(grep -l "plugin: 'views_block:category_grid" /tmp/config_export/block.block.*.yml 2>/dev/null | head -1)
    if [ -n "$BLOCK_FILE" ]; then
        if grep -q "region: content" "$BLOCK_FILE"; then
            BLOCK_IN_CONTENT="true"
        fi
    fi
fi

# 6. Build JSON
create_result_json /tmp/task_result.json \
    "field_storage_exists=$FIELD_STORAGE_EXISTS" \
    "field_instance_exists=$FIELD_INSTANCE_EXISTS" \
    "headphones_has_image=$HEADPHONES_HAS_IMAGE" \
    "keyboards_has_image=$KEYBOARDS_HAS_IMAGE" \
    "monitors_has_image=$MONITORS_HAS_IMAGE" \
    "view_exists=$VIEW_EXISTS" \
    "view_is_grid=$IS_GRID" \
    "view_shows_terms=$SHOWS_TERMS" \
    "view_has_image_field=$HAS_IMAGE_FIELD" \
    "block_placed=$BLOCK_PLACED" \
    "block_in_content=$BLOCK_IN_CONTENT" \
    "timestamp=$(date +%s)"

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export Complete ==="
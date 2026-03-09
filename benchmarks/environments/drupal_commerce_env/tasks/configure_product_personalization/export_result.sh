#!/bin/bash
# Export script for configure_product_personalization task
echo "=== Exporting Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

DRUPAL_ROOT="/var/www/html/drupal"
DRUSH="$DRUPAL_ROOT/vendor/bin/drush"

# 1. Identify the created field
# We look for any field storage on commerce_order_item that contains "engraving" in the name
echo "Searching for created field..."
cd "$DRUPAL_ROOT"
FIELD_STORAGE_NAME=$($DRUSH config:list | grep "field.storage.commerce_order_item" | grep -i "engraving" | head -n 1)

FIELD_FOUND="false"
FIELD_NAME=""
FIELD_TYPE=""
FIELD_LABEL=""
FIELD_INSTANCE_EXISTS="false"

if [ -n "$FIELD_STORAGE_NAME" ]; then
    FIELD_FOUND="true"
    # Extract field name (e.g., field_engraving_message) from config name (field.storage.commerce_order_item.field_engraving_message)
    FIELD_NAME=$(echo "$FIELD_STORAGE_NAME" | sed 's/field.storage.commerce_order_item.//')
    
    echo "Found field: $FIELD_NAME"
    
    # Get field type
    FIELD_TYPE=$($DRUSH config:get "$FIELD_STORAGE_NAME" type --format=string 2>/dev/null)
    
    # Check for field instance on the 'default' bundle
    INSTANCE_CONFIG_NAME="field.field.commerce_order_item.default.$FIELD_NAME"
    if $DRUSH config:get "$INSTANCE_CONFIG_NAME" > /dev/null 2>&1; then
        FIELD_INSTANCE_EXISTS="true"
        FIELD_LABEL=$($DRUSH config:get "$INSTANCE_CONFIG_NAME" label --format=string 2>/dev/null)
    fi
fi

# 2. Check Form Display Configuration
# We need to check if the field is enabled in the 'add_to_cart' form mode
FORM_DISPLAY_CONFIG="core.entity_form_display.commerce_order_item.default.add_to_cart"
FORM_DISPLAY_JSON="/tmp/form_display.json"

# Export the form display config to JSON
$DRUSH config:get "$FORM_DISPLAY_CONFIG" --format=json > "$FORM_DISPLAY_JSON" 2>/dev/null

# Check if the form display config actually exists (it might not if agent didn't configure it)
FORM_DISPLAY_EXISTS="false"
if [ -s "$FORM_DISPLAY_JSON" ] && grep -q "uuid" "$FORM_DISPLAY_JSON"; then
    FORM_DISPLAY_EXISTS="true"
else
    # Fallback: maybe they configured the 'default' form mode instead? (Common mistake)
    $DRUSH config:get "core.entity_form_display.commerce_order_item.default.default" --format=json > "/tmp/default_form_display.json" 2>/dev/null
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "field_found": $FIELD_FOUND,
    "field_name": "$FIELD_NAME",
    "field_type": "$FIELD_TYPE",
    "field_label": "$(json_escape "$FIELD_LABEL")",
    "field_instance_exists": $FIELD_INSTANCE_EXISTS,
    "form_display_exists": $FORM_DISPLAY_EXISTS,
    "form_display_json_path": "$FORM_DISPLAY_JSON",
    "timestamp": $(date +%s)
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json
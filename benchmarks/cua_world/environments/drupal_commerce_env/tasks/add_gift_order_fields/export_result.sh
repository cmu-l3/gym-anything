#!/bin/bash
# Export script for Add Gift Order Fields task
# Inspects Drupal configuration via Drush and exports to JSON

echo "=== Exporting Add Gift Order Fields Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Helper function to get config via Drush safely
get_drupal_config() {
    local config_name="$1"
    local key="$2"
    cd "$DRUPAL_DIR"
    # Use drush config:get with JSON output for precise parsing
    # If key is provided, extract it, otherwise return full json
    if [ -n "$key" ]; then
        $DRUSH config:get "$config_name" "$key" --format=json 2>/dev/null | jq -r ".\"$config_name\".\"$key\"" 2>/dev/null
    else
        $DRUSH config:get "$config_name" --format=json 2>/dev/null
    fi
}

# 1. Inspect 'Gift Message' Field
echo "Checking Gift Message field..."
MSG_STORAGE_EXISTS="false"
MSG_FIELD_EXISTS="false"
MSG_TYPE=""
MSG_REQUIRED=""
MSG_IN_FORM="false"

# Check storage config
MSG_STORAGE_JSON=$(get_drupal_config "field.storage.commerce_order.field_gift_message")
if [ -n "$MSG_STORAGE_JSON" ] && [ "$MSG_STORAGE_JSON" != "null" ]; then
    MSG_STORAGE_EXISTS="true"
    MSG_TYPE=$(echo "$MSG_STORAGE_JSON" | jq -r '.["field.storage.commerce_order.field_gift_message"].type')
fi

# Check instance config
MSG_FIELD_JSON=$(get_drupal_config "field.field.commerce_order.default.field_gift_message")
if [ -n "$MSG_FIELD_JSON" ] && [ "$MSG_FIELD_JSON" != "null" ]; then
    MSG_FIELD_EXISTS="true"
    MSG_REQUIRED=$(echo "$MSG_FIELD_JSON" | jq -r '.["field.field.commerce_order.default.field_gift_message"].required')
fi

# 2. Inspect 'Gift Wrap' Field
echo "Checking Gift Wrap field..."
WRAP_STORAGE_EXISTS="false"
WRAP_FIELD_EXISTS="false"
WRAP_TYPE=""
WRAP_REQUIRED=""
WRAP_IN_FORM="false"

# Check storage config
WRAP_STORAGE_JSON=$(get_drupal_config "field.storage.commerce_order.field_gift_wrap")
if [ -n "$WRAP_STORAGE_JSON" ] && [ "$WRAP_STORAGE_JSON" != "null" ]; then
    WRAP_STORAGE_EXISTS="true"
    WRAP_TYPE=$(echo "$WRAP_STORAGE_JSON" | jq -r '.["field.storage.commerce_order.field_gift_wrap"].type')
fi

# Check instance config
WRAP_FIELD_JSON=$(get_drupal_config "field.field.commerce_order.default.field_gift_wrap")
if [ -n "$WRAP_FIELD_JSON" ] && [ "$WRAP_FIELD_JSON" != "null" ]; then
    WRAP_FIELD_EXISTS="true"
    WRAP_REQUIRED=$(echo "$WRAP_FIELD_JSON" | jq -r '.["field.field.commerce_order.default.field_gift_wrap"].required')
fi

# 3. Inspect Form Display
echo "Checking Form Display..."
FORM_DISPLAY_JSON=$(get_drupal_config "core.entity_form_display.commerce_order.default.default")

if [ -n "$FORM_DISPLAY_JSON" ] && [ "$FORM_DISPLAY_JSON" != "null" ]; then
    # Check if fields are in the 'content' array (enabled) vs 'hidden'
    if echo "$FORM_DISPLAY_JSON" | jq -e '.["core.entity_form_display.commerce_order.default.default"].content.field_gift_message' > /dev/null; then
        MSG_IN_FORM="true"
    fi
    if echo "$FORM_DISPLAY_JSON" | jq -e '.["core.entity_form_display.commerce_order.default.default"].content.field_gift_wrap' > /dev/null; then
        WRAP_IN_FORM="true"
    fi
fi

# 4. Create Result JSON
# Use python for reliable JSON creation
python3 -c "
import json
import os

result = {
    'msg_storage_exists': $MSG_STORAGE_EXISTS,
    'msg_field_exists': $MSG_FIELD_EXISTS,
    'msg_type': '$MSG_TYPE',
    'msg_required': $([ "$MSG_REQUIRED" = "true" ] && echo "True" || echo "False"),
    'msg_in_form': $MSG_IN_FORM,
    'wrap_storage_exists': $WRAP_STORAGE_EXISTS,
    'wrap_field_exists': $WRAP_FIELD_EXISTS,
    'wrap_type': '$WRAP_TYPE',
    'wrap_required': $([ "$WRAP_REQUIRED" = "true" ] && echo "True" || echo "False"),
    'wrap_in_form': $WRAP_IN_FORM,
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="
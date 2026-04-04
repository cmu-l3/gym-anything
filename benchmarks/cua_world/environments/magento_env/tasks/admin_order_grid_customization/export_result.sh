#!/bin/bash
# Export script for Admin Order Grid Customization task

echo "=== Exporting Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get the bookmark configuration from the database
# We look for a bookmark where the identifier is 'Logistics View' OR the title is 'Logistics View'
# We fetch the raw JSON config blob
echo "Querying ui_bookmark table..."

# Magento stores grid views in ui_bookmark.
# namespace = 'sales_order_grid'
# identifier = 'Logistics View' (usually)
# current_state is stored in identifier='current'

BOOKMARK_JSON=$(magento_query "SELECT config FROM ui_bookmark WHERE namespace='sales_order_grid' AND (identifier='Logistics View' OR title='Logistics View') ORDER BY bookmark_id DESC LIMIT 1" 2>/dev/null)

if [ -z "$BOOKMARK_JSON" ]; then
    echo "No bookmark found with identifier/title 'Logistics View'"
    BOOKMARK_FOUND="false"
else
    echo "Bookmark found."
    BOOKMARK_FOUND="true"
fi

# Also check if the user just modified the 'current' view without saving it (for partial credit logic, though task requires saving)
CURRENT_JSON=$(magento_query "SELECT config FROM ui_bookmark WHERE namespace='sales_order_grid' AND identifier='current' AND user_id=1" 2>/dev/null)

# Escape JSON for embedding in our result JSON
# We use python to safely escape the inner JSON string if it exists
ESCAPED_BOOKMARK=$(python3 -c "import json, sys; print(json.dumps(sys.stdin.read().strip()))" <<< "$BOOKMARK_JSON")
ESCAPED_CURRENT=$(python3 -c "import json, sys; print(json.dumps(sys.stdin.read().strip()))" <<< "$CURRENT_JSON")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/grid_customization_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "bookmark_found": $BOOKMARK_FOUND,
    "bookmark_config": $ESCAPED_BOOKMARK,
    "current_config": $ESCAPED_CURRENT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/grid_customization_result.json

echo "Result exported to /tmp/grid_customization_result.json"
echo "=== Export Complete ==="
#!/bin/bash
# Export script for create_page_hierarchy task (post_task hook)

echo "=== Exporting create_page_hierarchy result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# Get initial page count and start time
INITIAL_PAGE_COUNT=$(cat /tmp/initial_page_count 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Get current page count
CURRENT_PAGE_COUNT=$(wp post list --post_type=page --post_status=publish --format=count --allow-root 2>/dev/null || echo "0")

echo "Initial published pages: $INITIAL_PAGE_COUNT"
echo "Current published pages: $CURRENT_PAGE_COUNT"

# Dump all published pages using WP-CLI to JSON format
# This provides ID, Title, Parent ID, Menu Order, Content, and Post Date
echo "Exporting page data..."
PAGE_DATA=$(wp post list --post_type=page --post_status=publish \
    --fields=ID,post_title,post_parent,menu_order,post_content,post_date \
    --format=json --allow-root 2>/dev/null)

if [ -z "$PAGE_DATA" ]; then
    PAGE_DATA="[]"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_page_count": $INITIAL_PAGE_COUNT,
    "current_page_count": $CURRENT_PAGE_COUNT,
    "task_start_time": $TASK_START_TIME,
    "pages": $PAGE_DATA,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/create_page_hierarchy_result.json 2>/dev/null || sudo rm -f /tmp/create_page_hierarchy_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_page_hierarchy_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_page_hierarchy_result.json
chmod 666 /tmp/create_page_hierarchy_result.json 2>/dev/null || sudo chmod 666 /tmp/create_page_hierarchy_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/create_page_hierarchy_result.json"
echo "=== Export complete ==="
#!/bin/bash
# Export script for Soft Launch Configuration task

echo "=== Exporting Soft Launch Configuration Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check CMS Page 'coming-soon'
echo "Checking for CMS page 'coming-soon'..."
PAGE_DATA=$(magento_query "SELECT page_id, title, is_active, content FROM cms_page WHERE identifier='coming-soon' LIMIT 1" 2>/dev/null)

PAGE_FOUND="false"
PAGE_ID=""
PAGE_TITLE=""
PAGE_ACTIVE="0"
PAGE_CONTENT=""

if [ -n "$PAGE_DATA" ]; then
    PAGE_FOUND="true"
    PAGE_ID=$(echo "$PAGE_DATA" | cut -f1)
    PAGE_TITLE=$(echo "$PAGE_DATA" | cut -f2)
    PAGE_ACTIVE=$(echo "$PAGE_DATA" | cut -f3)
    PAGE_CONTENT=$(echo "$PAGE_DATA" | cut -f4)
    echo "Page found: ID=$PAGE_ID, Title='$PAGE_TITLE', Active=$PAGE_ACTIVE"
else
    echo "CMS Page 'coming-soon' NOT found."
fi

# 2. Check Homepage Configuration
echo "Checking Homepage configuration..."
# Get value from core_config_data (scope_id 0 is default)
HOMEPAGE_CONFIG=$(magento_query "SELECT value FROM core_config_data WHERE path='web/default/cms_home_page' ORDER BY scope_id DESC LIMIT 1" 2>/dev/null)
echo "Current Homepage Config: '$HOMEPAGE_CONFIG'"

# 3. Check Demo Notice Configuration
echo "Checking Demo Notice configuration..."
DEMO_NOTICE_CONFIG=$(magento_query "SELECT value FROM core_config_data WHERE path='design/head/demonotice' ORDER BY scope_id DESC LIMIT 1" 2>/dev/null)
echo "Current Demo Notice Config: '$DEMO_NOTICE_CONFIG'"

# Escape content for JSON
PAGE_CONTENT_ESC=$(echo "$PAGE_CONTENT" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')
PAGE_TITLE_ESC=$(echo "$PAGE_TITLE" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/soft_launch_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "page_found": $PAGE_FOUND,
    "page_id": "${PAGE_ID:-}",
    "page_title": "$PAGE_TITLE_ESC",
    "page_active": "${PAGE_ACTIVE:-0}",
    "page_content": "$PAGE_CONTENT_ESC",
    "homepage_config": "${HOMEPAGE_CONFIG:-}",
    "demo_notice_config": "${DEMO_NOTICE_CONFIG:-}",
    "initial_homepage": "$(cat /tmp/initial_homepage_config 2>/dev/null || echo "")",
    "initial_demo_notice": "$(cat /tmp/initial_demonotice_config 2>/dev/null || echo "")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/soft_launch_result.json

echo ""
cat /tmp/soft_launch_result.json
echo ""
echo "=== Export Complete ==="
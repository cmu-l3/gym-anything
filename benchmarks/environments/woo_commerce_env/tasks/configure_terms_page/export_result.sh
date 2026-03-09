#!/bin/bash
# Export script for Configure Terms Page task

echo "=== Exporting Configure Terms Page Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get the current WooCommerce Terms Page setting
CURRENT_SETTING_ID=$(wc_query "SELECT option_value FROM wp_options WHERE option_name = 'woocommerce_terms_page_id'" 2>/dev/null)
INITIAL_SETTING_ID=$(cat /tmp/initial_terms_id.txt 2>/dev/null || echo "0")

# 2. Get details about the page configured in the setting (if any)
PAGE_EXISTS="false"
PAGE_TITLE=""
PAGE_CONTENT=""
PAGE_STATUS=""
PAGE_DATE=""
PAGE_ID=""

if [ -n "$CURRENT_SETTING_ID" ] && [ "$CURRENT_SETTING_ID" != "0" ]; then
    # Helper to fetch specific fields for the ID found in settings
    PAGE_DATA=$(wc_query "SELECT ID, post_title, post_content, post_status, post_date_gmt 
                          FROM wp_posts WHERE ID = $CURRENT_SETTING_ID LIMIT 1" 2>/dev/null)
    
    if [ -n "$PAGE_DATA" ]; then
        PAGE_EXISTS="true"
        PAGE_ID=$(echo "$PAGE_DATA" | cut -f1)
        PAGE_TITLE=$(echo "$PAGE_DATA" | cut -f2)
        PAGE_CONTENT=$(echo "$PAGE_DATA" | cut -f3)
        PAGE_STATUS=$(echo "$PAGE_DATA" | cut -f4)
        PAGE_DATE=$(echo "$PAGE_DATA" | cut -f5)
    fi
fi

# 3. Fallback check: Did they create the page but fail to link it?
# Search for a page with the expected title created recently
FALLBACK_PAGE_FOUND="false"
FALLBACK_ID=""
if [ "$PAGE_EXISTS" = "false" ] || [ "$PAGE_TITLE" != "Terms of Service" ]; then
    echo "Checking for unlinked 'Terms of Service' page..."
    FALLBACK_DATA=$(wc_query "SELECT ID, post_title, post_content, post_status, post_date_gmt 
                              FROM wp_posts 
                              WHERE post_type = 'page' 
                              AND post_title = 'Terms of Service' 
                              ORDER BY ID DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$FALLBACK_DATA" ]; then
        FALLBACK_PAGE_FOUND="true"
        FALLBACK_ID=$(echo "$FALLBACK_DATA" | cut -f1)
        # We only record this for partial credit/debugging; 
        # the primary requirement is that it is LINKED in settings.
        echo "Found unlinked page ID: $FALLBACK_ID"
    fi
fi

# 4. JSON Escaping
# We use Python for reliable escaping of the content which might contain special chars
PAGE_TITLE_ESC=$(json_escape "$PAGE_TITLE")
PAGE_CONTENT_ESC=$(json_escape "$PAGE_CONTENT")
PAGE_DATE_ESC=$(json_escape "$PAGE_DATE")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "initial_setting_id": "${INITIAL_SETTING_ID}",
    "current_setting_id": "${CURRENT_SETTING_ID:-0}",
    "page_linked_in_settings": {
        "exists": $PAGE_EXISTS,
        "id": "${PAGE_ID:-0}",
        "title": "$PAGE_TITLE_ESC",
        "content": "$PAGE_CONTENT_ESC",
        "status": "$PAGE_STATUS",
        "post_date_gmt": "$PAGE_DATE_ESC"
    },
    "fallback_search": {
        "found": $FALLBACK_PAGE_FOUND,
        "id": "${FALLBACK_ID:-0}"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo ""
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="
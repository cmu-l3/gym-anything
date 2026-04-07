#!/bin/bash
# Export script for schedule_content_series task (post_task hook)

echo "=== Exporting schedule_content_series result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Helper function to get post information safely
function get_post_info() {
    local title="$1"
    local prefix="$2"
    
    # Try exact match
    local pid=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title = '$title' AND post_type='post' ORDER BY ID DESC LIMIT 1" | tr -d '\r\n')
    
    # Fallback to case-insensitive and trimmed match
    if [ -z "$pid" ]; then
        pid=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$title')) AND post_type='post' ORDER BY ID DESC LIMIT 1" | tr -d '\r\n')
    fi

    if [ -n "$pid" ]; then
        local status=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$pid" | tr -d '\r\n')
        local pdate=$(wp_db_query "SELECT post_date FROM wp_posts WHERE ID=$pid" | tr -d '\r\n')
        local len=$(wp_db_query "SELECT LENGTH(post_content) FROM wp_posts WHERE ID=$pid" | tr -d '\r\n')
        local cats=$(get_post_categories "$pid" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '\r\n')
        local tags=$(get_post_tags "$pid" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '\r\n')

        echo "    \"${prefix}_found\": true,"
        echo "    \"${prefix}_status\": \"$status\","
        echo "    \"${prefix}_date\": \"$pdate\","
        echo "    \"${prefix}_len\": ${len:-0},"
        echo "    \"${prefix}_cats\": \"$cats\","
        echo "    \"${prefix}_tags\": \"$tags\""
    else
        echo "    \"${prefix}_found\": false,"
        echo "    \"${prefix}_status\": \"\","
        echo "    \"${prefix}_date\": \"\","
        echo "    \"${prefix}_len\": 0,"
        echo "    \"${prefix}_cats\": \"\","
        echo "    \"${prefix}_tags\": \"\""
    fi
}

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
$(get_post_info "The Future of Renewable Energy: A 2026 Outlook" "p1"),
$(get_post_info "Solar Power Breakthroughs Driving Global Adoption" "p2"),
$(get_post_info "The Economics of Wind Energy in Coastal Communities" "p3"),
    "export_timestamp": "$(date +%s)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/schedule_content_series_result.json 2>/dev/null || sudo rm -f /tmp/schedule_content_series_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/schedule_content_series_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/schedule_content_series_result.json
chmod 666 /tmp/schedule_content_series_result.json 2>/dev/null || sudo chmod 666 /tmp/schedule_content_series_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/schedule_content_series_result.json"
cat /tmp/schedule_content_series_result.json
echo ""
echo "=== Export complete ==="
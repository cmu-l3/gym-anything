#!/bin/bash
# Export script for manage_editorial_calendar task

echo "=== Exporting manage_editorial_calendar result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Helper function to extract and format post data
get_post_export() {
    local title="$1"
    # Query database for newest post matching title
    local data=$(wp_db_query "SELECT ID, post_status, post_date FROM wp_posts WHERE LOWER(TRIM(post_title))=LOWER(TRIM('$title')) AND post_type='post' ORDER BY ID DESC LIMIT 1" | tr '\t' '|')
    
    local id=$(echo "$data" | cut -d'|' -f1 | tr -d '\r\n')
    local status=$(echo "$data" | cut -d'|' -f2 | tr -d '\r\n')
    local date=$(echo "$data" | cut -d'|' -f3 | tr -d '\r\n')
    local len=0
    local cats=""

    if [ -n "$id" ]; then
        len=$(wp_db_query "SELECT LENGTH(post_content) FROM wp_posts WHERE ID='$id'" 2>/dev/null | tr -d '\r\n' || echo "0")
        cats=$(get_post_categories "$id" 2>/dev/null | tr -d '\r\n' || echo "")
    fi

    # Return valid JSON fragment
    echo "{\"id\": \"$id\", \"status\": \"$status\", \"date\": \"$date\", \"len\": ${len:-0}, \"cats\": \"$cats\"}"
}

# 1. Check if Category exists
CAT_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id=tt.term_id WHERE tt.taxonomy='category' AND LOWER(t.name)='editorial picks'" 2>/dev/null | tr -d '\r\n' || echo "0")
if [ "$CAT_COUNT" -gt 0 ]; then
    CAT_EXISTS="true"
else
    CAT_EXISTS="false"
fi

# 2. Get data for the 3 new scheduled posts
P1_JSON=$(get_post_export "Weekly News Roundup: Tech Industry Updates")
P2_JSON=$(get_post_export "Interview: The Future of Digital Media")
P3_JSON=$(get_post_export "Editorial: Why Open Source Matters")

# 3. Get data for the existing posts being modified
GS_JSON=$(get_post_export "Getting Started with WordPress")
D1_JSON=$(get_post_export "10 Essential WordPress Plugins Every Site Needs")
D2_JSON=$(get_post_export "The Art of Writing Engaging Blog Content")

# 4. Get Sticky Posts configuration
# Returns a JSON array of post IDs like [12, 15] or empty
STICKY_RAW=$(wp_cli option get sticky_posts --format=json 2>/dev/null || echo "[]")
if [ -z "$STICKY_RAW" ]; then
    STICKY_RAW="[]"
fi

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "cat_exists": $CAT_EXISTS,
    "p1": $P1_JSON,
    "p2": $P2_JSON,
    "p3": $P3_JSON,
    "gs": $GS_JSON,
    "d1": $D1_JSON,
    "d2": $D2_JSON,
    "sticky_posts": $STICKY_RAW,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location safely
rm -f /tmp/manage_editorial_calendar_result.json 2>/dev/null || sudo rm -f /tmp/manage_editorial_calendar_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/manage_editorial_calendar_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/manage_editorial_calendar_result.json
chmod 666 /tmp/manage_editorial_calendar_result.json 2>/dev/null || sudo chmod 666 /tmp/manage_editorial_calendar_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/manage_editorial_calendar_result.json"
cat /tmp/manage_editorial_calendar_result.json
echo ""
echo "=== Export complete ==="
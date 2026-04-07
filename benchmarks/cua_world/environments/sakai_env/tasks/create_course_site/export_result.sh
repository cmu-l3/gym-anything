#!/bin/bash
# Export script for Create Course Site task

echo "=== Exporting Create Course Site Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type sakai_query &>/dev/null; then
    sakai_query() {
        docker exec sakai-db mysql -u sakai -psakaipass sakai -N -B -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
    safe_write_json() {
        local temp_file="$1"; local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"; echo "Result saved to $dest_path"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Target site
TARGET_SITE="CHEM201"

# Get baseline
INITIAL_SITE_COUNT=$(cat /tmp/initial_site_count 2>/dev/null || echo "0")

# Get current site count
CURRENT_SITE_COUNT=$(sakai_query "SELECT COUNT(*) FROM SAKAI_SITE WHERE SITE_ID NOT LIKE '~%' AND SITE_ID NOT LIKE '!%'" | tr -d '[:space:]')
CURRENT_SITE_COUNT=${CURRENT_SITE_COUNT:-0}

echo "Site count: initial=$INITIAL_SITE_COUNT, current=$CURRENT_SITE_COUNT"

# Look for the target site
SITE_DATA=$(sakai_query "SELECT SITE_ID, TITLE, TYPE, PUBLISHED FROM SAKAI_SITE WHERE SITE_ID='$TARGET_SITE' LIMIT 1")

SITE_FOUND="false"
SITE_ID=""
SITE_TITLE=""
SITE_TYPE=""
SITE_PUBLISHED="0"
TOOL_COUNT="0"
TOOL_LIST=""

if [ -n "$SITE_DATA" ]; then
    SITE_FOUND="true"
    SITE_ID=$(echo "$SITE_DATA" | cut -f1 | tr -d '[:space:]')
    SITE_TITLE=$(echo "$SITE_DATA" | cut -f2)
    SITE_TYPE=$(echo "$SITE_DATA" | cut -f3 | tr -d '[:space:]')
    SITE_PUBLISHED=$(echo "$SITE_DATA" | cut -f4 | tr -d '[:space:]')

    # Count tools
    TOOL_COUNT=$(sakai_query "SELECT COUNT(*) FROM SAKAI_SITE_TOOL WHERE SITE_ID='$TARGET_SITE'" | tr -d '[:space:]')
    TOOL_COUNT=${TOOL_COUNT:-0}

    # Get tool list
    TOOL_LIST=$(sakai_query "SELECT REGISTRATION FROM SAKAI_SITE_TOOL WHERE SITE_ID='$TARGET_SITE'" | tr '\n' ',' | sed 's/,$//')

    # Get description
    SITE_DESC=$(sakai_query "SELECT DESCRIPTION FROM SAKAI_SITE WHERE SITE_ID='$TARGET_SITE'" 2>/dev/null || echo "")

    # Get membership count
    MEMBER_COUNT=$(sakai_query "SELECT COUNT(*) FROM SAKAI_SITE_USER WHERE SITE_ID='$TARGET_SITE'" | tr -d '[:space:]')

    echo "Site found: ID=$SITE_ID, Title='$SITE_TITLE', Type=$SITE_TYPE, Published=$SITE_PUBLISHED"
    echo "Tools ($TOOL_COUNT): $TOOL_LIST"
    echo "Members: $MEMBER_COUNT"
else
    echo "Target site '$TARGET_SITE' NOT found"
    # Also check by title in case site ID is different
    ALT_DATA=$(sakai_query "SELECT SITE_ID, TITLE, TYPE, PUBLISHED FROM SAKAI_SITE WHERE LOWER(TITLE) LIKE '%chem 201%' OR LOWER(TITLE) LIKE '%general chemistry ii%' LIMIT 1")
    if [ -n "$ALT_DATA" ]; then
        SITE_FOUND="true"
        SITE_ID=$(echo "$ALT_DATA" | cut -f1 | tr -d '[:space:]')
        SITE_TITLE=$(echo "$ALT_DATA" | cut -f2)
        SITE_TYPE=$(echo "$ALT_DATA" | cut -f3 | tr -d '[:space:]')
        SITE_PUBLISHED=$(echo "$ALT_DATA" | cut -f4 | tr -d '[:space:]')
        TOOL_COUNT=$(sakai_query "SELECT COUNT(*) FROM SAKAI_SITE_TOOL WHERE SITE_ID='$SITE_ID'" | tr -d '[:space:]')
        TOOL_LIST=$(sakai_query "SELECT REGISTRATION FROM SAKAI_SITE_TOOL WHERE SITE_ID='$SITE_ID'" | tr '\n' ',' | sed 's/,$//')
        echo "Found site by title: ID=$SITE_ID, Title='$SITE_TITLE'"
    fi
fi

# Escape for JSON
SITE_TITLE_ESC=$(echo "$SITE_TITLE" | sed 's/"/\\"/g')
SITE_DESC_ESC=$(echo "${SITE_DESC:-}" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/create_course_site_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_site_count": ${INITIAL_SITE_COUNT:-0},
    "current_site_count": ${CURRENT_SITE_COUNT:-0},
    "site_found": $SITE_FOUND,
    "site_id": "$SITE_ID",
    "site_title": "$SITE_TITLE_ESC",
    "site_type": "${SITE_TYPE:-}",
    "site_published": ${SITE_PUBLISHED:-0},
    "site_description": "$SITE_DESC_ESC",
    "tool_count": ${TOOL_COUNT:-0},
    "tool_list": "$TOOL_LIST",
    "member_count": ${MEMBER_COUNT:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_course_site_result.json

echo ""
cat /tmp/create_course_site_result.json
echo ""
echo "=== Export Complete ==="

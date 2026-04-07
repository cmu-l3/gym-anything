#!/bin/bash
# Export script for Post Announcement task

echo "=== Exporting Post Announcement Result ==="

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

TARGET_SITE="HIST201"

# Get baseline
INITIAL_ANNOUNCEMENT_COUNT=$(cat /tmp/initial_announcement_count 2>/dev/null || echo "0")

# Get current announcement count
CURRENT_ANNOUNCEMENT_COUNT=$(sakai_query "SELECT COUNT(*) FROM ANNOUNCEMENT_MESSAGE WHERE CHANNEL_ID LIKE '%/channel/$TARGET_SITE/main%'" 2>/dev/null | tr -d '[:space:]')
CURRENT_ANNOUNCEMENT_COUNT=${CURRENT_ANNOUNCEMENT_COUNT:-0}

echo "Announcement count: initial=$INITIAL_ANNOUNCEMENT_COUNT, current=$CURRENT_ANNOUNCEMENT_COUNT"

# Look for the target announcement by title
ANNOUNCEMENT_DATA=$(sakai_query "SELECT MESSAGE_ID, OWNER FROM ANNOUNCEMENT_MESSAGE WHERE CHANNEL_ID LIKE '%/channel/$TARGET_SITE/main%' ORDER BY DATE_CURRENT DESC LIMIT 1" 2>/dev/null)

ANNOUNCEMENT_FOUND="false"
ANNOUNCEMENT_ID=""
ANNOUNCEMENT_TITLE=""
ANNOUNCEMENT_BODY=""
HAS_EXPECTED_CONTENT="false"

if [ -n "$ANNOUNCEMENT_DATA" ]; then
    ANNOUNCEMENT_ID=$(echo "$ANNOUNCEMENT_DATA" | cut -f1 | tr -d '[:space:]')

    # Get announcement XML content from ANNOUNCEMENT_MESSAGE
    # Sakai stores announcement data as XML in the MESSAGE_ID referenced content
    # Try to extract title and body
    ANN_XML=$(sakai_query "SELECT XML FROM ANNOUNCEMENT_MESSAGE WHERE MESSAGE_ID='$ANNOUNCEMENT_ID' AND CHANNEL_ID LIKE '%/channel/$TARGET_SITE/main%'" 2>/dev/null || echo "")

    if [ -n "$ANN_XML" ]; then
        # Extract title from XML (subject attribute or element)
        ANNOUNCEMENT_TITLE=$(echo "$ANN_XML" | grep -oP 'subject="[^"]*"' | head -1 | sed 's/subject="//;s/"//' || echo "")
        if [ -z "$ANNOUNCEMENT_TITLE" ]; then
            # Try header/subject pattern
            ANNOUNCEMENT_TITLE=$(echo "$ANN_XML" | grep -oP '<header[^>]*subject="[^"]*"' | head -1 | sed 's/.*subject="//;s/"//' || echo "")
        fi

        # Check body content for expected keywords
        if echo "$ANN_XML" | grep -qi "midterm.*study\|study.*guide\|review session"; then
            ANNOUNCEMENT_FOUND="true"
            HAS_EXPECTED_CONTENT="true"
        elif echo "$ANN_XML" | grep -qi "midterm\|exam\|review"; then
            ANNOUNCEMENT_FOUND="true"
            HAS_EXPECTED_CONTENT="false"
        fi
    fi

    # If we couldn't parse XML, check if new announcements were created
    if [ "$ANNOUNCEMENT_FOUND" = "false" ] && [ "${CURRENT_ANNOUNCEMENT_COUNT:-0}" -gt "${INITIAL_ANNOUNCEMENT_COUNT:-0}" ]; then
        ANNOUNCEMENT_FOUND="true"
    fi

    echo "Latest announcement: ID=$ANNOUNCEMENT_ID, Title='$ANNOUNCEMENT_TITLE'"
fi

# Also check via Sakai's entity broker REST API
if [ "$ANNOUNCEMENT_FOUND" = "false" ]; then
    # Try REST API
    SESSION=$(curl -s -X POST "http://localhost:8080/sakai-ws/rest/login/login" \
        -d "id=admin" -d "pw=admin" 2>/dev/null | tr -d '[:space:]')

    if [ -n "$SESSION" ] && [ "$SESSION" != "null" ]; then
        API_RESULT=$(curl -s "http://localhost:8080/direct/announcement/site/$TARGET_SITE.json" \
            -H "Cookie: SAKAI_SESSION=$SESSION" 2>/dev/null || echo "{}")

        if echo "$API_RESULT" | python3 -c "import sys,json; data=json.load(sys.stdin); msgs=data.get('announcement_collection',[]); print(len(msgs))" 2>/dev/null | grep -q '[1-9]'; then
            ANNOUNCEMENT_FOUND="true"
            # Get title of most recent
            ANNOUNCEMENT_TITLE=$(echo "$API_RESULT" | python3 -c "
import sys,json
data=json.load(sys.stdin)
msgs=data.get('announcement_collection',[])
if msgs:
    print(msgs[0].get('title',''))
" 2>/dev/null || echo "")
            # Check content
            CONTENT_CHECK=$(echo "$API_RESULT" | python3 -c "
import sys,json
data=json.load(sys.stdin)
msgs=data.get('announcement_collection',[])
if msgs:
    body=msgs[0].get('body','').lower()
    if 'midterm' in body and ('study' in body or 'review' in body):
        print('true')
    else:
        print('false')
else:
    print('false')
" 2>/dev/null || echo "false")
            HAS_EXPECTED_CONTENT="$CONTENT_CHECK"
        fi
    fi
fi

# Escape for JSON
ANNOUNCEMENT_TITLE_ESC=$(echo "$ANNOUNCEMENT_TITLE" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/post_announcement_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_site": "$TARGET_SITE",
    "initial_announcement_count": ${INITIAL_ANNOUNCEMENT_COUNT:-0},
    "current_announcement_count": ${CURRENT_ANNOUNCEMENT_COUNT:-0},
    "announcement_found": $ANNOUNCEMENT_FOUND,
    "announcement_id": "$ANNOUNCEMENT_ID",
    "announcement_title": "$ANNOUNCEMENT_TITLE_ESC",
    "has_expected_content": $HAS_EXPECTED_CONTENT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/post_announcement_result.json

echo ""
cat /tmp/post_announcement_result.json
echo ""
echo "=== Export Complete ==="

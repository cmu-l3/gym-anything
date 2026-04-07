#!/bin/bash
# Export script for Create Assignment task

echo "=== Exporting Create Assignment Result ==="

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

TARGET_SITE="BIO101"

# Get baseline
INITIAL_ASSIGNMENT_COUNT=$(cat /tmp/initial_assignment_count 2>/dev/null || echo "0")

# Get current assignment count
CURRENT_ASSIGNMENT_COUNT=$(sakai_query "SELECT COUNT(*) FROM ASN_ASSIGNMENT WHERE CONTEXT='$TARGET_SITE' AND DELETED=0" 2>/dev/null | tr -d '[:space:]')
CURRENT_ASSIGNMENT_COUNT=${CURRENT_ASSIGNMENT_COUNT:-0}

echo "Assignment count: initial=$INITIAL_ASSIGNMENT_COUNT, current=$CURRENT_ASSIGNMENT_COUNT"

# Look for the target assignment (case-insensitive match)
ASSIGNMENT_DATA=$(sakai_query "SELECT ASSIGNMENT_ID, TITLE, CONTEXT, MAX_GRADE_POINT FROM ASN_ASSIGNMENT WHERE CONTEXT='$TARGET_SITE' AND DELETED=0 AND LOWER(TITLE) LIKE '%midterm research paper%' AND LOWER(TITLE) LIKE '%cell biology%' ORDER BY CREATED_DATE DESC LIMIT 1" 2>/dev/null)

ASSIGNMENT_FOUND="false"
ASSIGNMENT_ID=""
ASSIGNMENT_TITLE=""
ASSIGNMENT_CONTEXT=""
MAX_GRADE="0"
HAS_INSTRUCTIONS="false"

if [ -n "$ASSIGNMENT_DATA" ]; then
    ASSIGNMENT_FOUND="true"
    ASSIGNMENT_ID=$(echo "$ASSIGNMENT_DATA" | cut -f1 | tr -d '[:space:]')
    ASSIGNMENT_TITLE=$(echo "$ASSIGNMENT_DATA" | cut -f2)
    ASSIGNMENT_CONTEXT=$(echo "$ASSIGNMENT_DATA" | cut -f3 | tr -d '[:space:]')
    MAX_GRADE=$(echo "$ASSIGNMENT_DATA" | cut -f4 | tr -d '[:space:]')

    # Check if instructions contain expected content
    INSTRUCTIONS=$(sakai_query "SELECT INSTRUCTIONS FROM ASN_ASSIGNMENT WHERE ASSIGNMENT_ID='$ASSIGNMENT_ID'" 2>/dev/null || echo "")
    if echo "$INSTRUCTIONS" | grep -qi "research paper\|cell biology\|mitochondria"; then
        HAS_INSTRUCTIONS="true"
    fi

    echo "Assignment found: ID=$ASSIGNMENT_ID, Title='$ASSIGNMENT_TITLE', MaxGrade=$MAX_GRADE"
else
    echo "Target assignment NOT found in BIO101"
    # Check with broader match
    ALT_DATA=$(sakai_query "SELECT ASSIGNMENT_ID, TITLE, CONTEXT, MAX_GRADE_POINT FROM ASN_ASSIGNMENT WHERE CONTEXT='$TARGET_SITE' AND DELETED=0 AND (LOWER(TITLE) LIKE '%research paper%' OR LOWER(TITLE) LIKE '%cell biology%') ORDER BY CREATED_DATE DESC LIMIT 1" 2>/dev/null)
    if [ -n "$ALT_DATA" ]; then
        ASSIGNMENT_FOUND="true"
        ASSIGNMENT_ID=$(echo "$ALT_DATA" | cut -f1 | tr -d '[:space:]')
        ASSIGNMENT_TITLE=$(echo "$ALT_DATA" | cut -f2)
        ASSIGNMENT_CONTEXT=$(echo "$ALT_DATA" | cut -f3 | tr -d '[:space:]')
        MAX_GRADE=$(echo "$ALT_DATA" | cut -f4 | tr -d '[:space:]')
        echo "Found assignment by partial match: ID=$ASSIGNMENT_ID, Title='$ASSIGNMENT_TITLE'"
    fi
fi

# Escape for JSON
ASSIGNMENT_TITLE_ESC=$(echo "$ASSIGNMENT_TITLE" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/create_assignment_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_site": "$TARGET_SITE",
    "initial_assignment_count": ${INITIAL_ASSIGNMENT_COUNT:-0},
    "current_assignment_count": ${CURRENT_ASSIGNMENT_COUNT:-0},
    "assignment_found": $ASSIGNMENT_FOUND,
    "assignment_id": "$ASSIGNMENT_ID",
    "assignment_title": "$ASSIGNMENT_TITLE_ESC",
    "assignment_context": "$ASSIGNMENT_CONTEXT",
    "max_grade": "${MAX_GRADE:-0}",
    "has_instructions": $HAS_INSTRUCTIONS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_assignment_result.json

echo ""
cat /tmp/create_assignment_result.json
echo ""
echo "=== Export Complete ==="

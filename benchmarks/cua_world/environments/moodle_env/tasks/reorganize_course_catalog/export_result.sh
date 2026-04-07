#!/bin/bash
# Export script for Reorganize Course Catalog task

echo "=== Exporting Reorganize Course Catalog Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
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

# 1. Inspect "Life Sciences" Category
echo "Checking 'Life Sciences' category..."
# Select using name or idnumber to be robust
LIFESCI_DATA=$(moodle_query "SELECT id, name, idnumber, description, parent, visible FROM mdl_course_categories WHERE idnumber='LIFESCI' OR name='Life Sciences' ORDER BY id DESC LIMIT 1")

LIFESCI_FOUND="false"
LIFESCI_ID=""
LIFESCI_NAME=""
LIFESCI_IDNUM=""
LIFESCI_DESC=""
LIFESCI_PARENT=""
LIFESCI_VISIBLE=""

if [ -n "$LIFESCI_DATA" ]; then
    LIFESCI_FOUND="true"
    LIFESCI_ID=$(echo "$LIFESCI_DATA" | cut -f1 | tr -d '[:space:]')
    LIFESCI_NAME=$(echo "$LIFESCI_DATA" | cut -f2)
    LIFESCI_IDNUM=$(echo "$LIFESCI_DATA" | cut -f3)
    LIFESCI_DESC=$(echo "$LIFESCI_DATA" | cut -f4)
    LIFESCI_PARENT=$(echo "$LIFESCI_DATA" | cut -f5 | tr -d '[:space:]')
    LIFESCI_VISIBLE=$(echo "$LIFESCI_DATA" | cut -f6 | tr -d '[:space:]')
fi

# 2. Inspect "Archived Life Sciences" Category
echo "Checking 'Archived Life Sciences' sub-category..."
ARCHIVE_DATA=$(moodle_query "SELECT id, name, idnumber, parent, visible FROM mdl_course_categories WHERE idnumber='LIFESCI_ARCHIVE' OR name='Archived Life Sciences' ORDER BY id DESC LIMIT 1")

ARCHIVE_FOUND="false"
ARCHIVE_ID=""
ARCHIVE_NAME=""
ARCHIVE_IDNUM=""
ARCHIVE_PARENT=""
ARCHIVE_VISIBLE=""

if [ -n "$ARCHIVE_DATA" ]; then
    ARCHIVE_FOUND="true"
    ARCHIVE_ID=$(echo "$ARCHIVE_DATA" | cut -f1 | tr -d '[:space:]')
    ARCHIVE_NAME=$(echo "$ARCHIVE_DATA" | cut -f2)
    ARCHIVE_IDNUM=$(echo "$ARCHIVE_DATA" | cut -f3)
    ARCHIVE_PARENT=$(echo "$ARCHIVE_DATA" | cut -f4 | tr -d '[:space:]')
    ARCHIVE_VISIBLE=$(echo "$ARCHIVE_DATA" | cut -f5 | tr -d '[:space:]')
fi

# 3. Check BIO101 Location
echo "Checking BIO101 location..."
BIO101_DATA=$(moodle_query "SELECT id, category FROM mdl_course WHERE shortname='BIO101'")
BIO101_CAT_ID=""
if [ -n "$BIO101_DATA" ]; then
    BIO101_CAT_ID=$(echo "$BIO101_DATA" | cut -f2 | tr -d '[:space:]')
fi

# Escape JSON strings
LIFESCI_DESC_ESC=$(echo "$LIFESCI_DESC" | sed 's/"/\\"/g' | tr -d '\n')
LIFESCI_NAME_ESC=$(echo "$LIFESCI_NAME" | sed 's/"/\\"/g')
ARCHIVE_NAME_ESC=$(echo "$ARCHIVE_NAME" | sed 's/"/\\"/g')

# Create JSON
TEMP_JSON=$(mktemp /tmp/reorganize_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "lifesci_found": $LIFESCI_FOUND,
    "lifesci": {
        "id": "$LIFESCI_ID",
        "name": "$LIFESCI_NAME_ESC",
        "idnumber": "$LIFESCI_IDNUM",
        "description": "$LIFESCI_DESC_ESC",
        "parent": "${LIFESCI_PARENT:-0}",
        "visible": "${LIFESCI_VISIBLE:-1}"
    },
    "archive_found": $ARCHIVE_FOUND,
    "archive": {
        "id": "$ARCHIVE_ID",
        "name": "$ARCHIVE_NAME_ESC",
        "idnumber": "$ARCHIVE_IDNUM",
        "parent": "${ARCHIVE_PARENT:-0}",
        "visible": "${ARCHIVE_VISIBLE:-1}"
    },
    "bio101_category_id": "${BIO101_CAT_ID:-0}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/reorganize_result.json

echo ""
cat /tmp/reorganize_result.json
echo ""
echo "=== Export Complete ==="
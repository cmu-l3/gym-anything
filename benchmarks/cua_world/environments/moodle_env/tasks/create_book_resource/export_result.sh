#!/bin/bash
# Export script for Create Book Resource task

echo "=== Exporting Create Book Resource Result ==="

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
    moodle_query_headers() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
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

# Get BIO101 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
COURSE_ID=${COURSE_ID:-0}

# Get baseline
INITIAL_BOOK_COUNT=$(cat /tmp/initial_book_count 2>/dev/null || echo "0")

# Get current book count
CURRENT_BOOK_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_book WHERE course=$COURSE_ID" | tr -d '[:space:]')
CURRENT_BOOK_COUNT=${CURRENT_BOOK_COUNT:-0}

echo "Book count: initial=$INITIAL_BOOK_COUNT, current=$CURRENT_BOOK_COUNT"

# Look for the target book
# Use LIKE for name matching to be robust against minor spacing issues
BOOK_DATA=$(moodle_query "SELECT id, name, numbering, course FROM mdl_book WHERE course=$COURSE_ID AND LOWER(name) LIKE '%biology lab manual%' AND LOWER(name) LIKE '%cell biology%' ORDER BY id DESC LIMIT 1")

BOOK_FOUND="false"
BOOK_ID=""
BOOK_NAME=""
BOOK_NUMBERING=""
BOOK_VISIBLE="0"

CHAPTERS_JSON="[]"

if [ -n "$BOOK_DATA" ]; then
    BOOK_FOUND="true"
    BOOK_ID=$(echo "$BOOK_DATA" | cut -f1 | tr -d '[:space:]')
    BOOK_NAME=$(echo "$BOOK_DATA" | cut -f2)
    BOOK_NUMBERING=$(echo "$BOOK_DATA" | cut -f3 | tr -d '[:space:]')
    
    # Check visibility in course_modules
    # We need the module ID for 'book'
    MODULE_ID=$(moodle_query "SELECT id FROM mdl_modules WHERE name='book'" | tr -d '[:space:]')
    if [ -n "$MODULE_ID" ]; then
        BOOK_VISIBLE=$(moodle_query "SELECT visible FROM mdl_course_modules WHERE module=$MODULE_ID AND instance=$BOOK_ID" | tr -d '[:space:]')
    fi
    
    echo "Book found: ID=$BOOK_ID, Name='$BOOK_NAME', Numbering=$BOOK_NUMBERING, Visible=$BOOK_VISIBLE"
    
    # Get chapters for this book
    # We need to construct a JSON array of chapters manually or using python
    # Using python for cleaner JSON generation from SQL output
    
    # Dump chapters to a temp file
    moodle_query "SELECT title, subchapter, pagenum, content FROM mdl_book_chapters WHERE bookid=$BOOK_ID ORDER BY pagenum ASC" > /tmp/chapters_dump.txt
    
    # Python script to convert tab-separated dump to JSON
    python3 -c "
import json
import sys

chapters = []
try:
    with open('/tmp/chapters_dump.txt', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 3:
                title = parts[0]
                subchapter = parts[1]
                pagenum = parts[2]
                content = parts[3] if len(parts) > 3 else ''
                chapters.append({
                    'title': title,
                    'subchapter': int(subchapter),
                    'pagenum': int(pagenum),
                    'content': content
                })
except Exception as e:
    sys.stderr.write(str(e))

print(json.dumps(chapters))
" > /tmp/chapters_json.txt

    CHAPTERS_JSON=$(cat /tmp/chapters_json.txt)
else
    echo "Target book NOT found in BIO101"
fi

# Escape for JSON
BOOK_NAME_ESC=$(echo "$BOOK_NAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/create_book_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_book_count": ${INITIAL_BOOK_COUNT:-0},
    "current_book_count": ${CURRENT_BOOK_COUNT:-0},
    "book_found": $BOOK_FOUND,
    "book_id": "$BOOK_ID",
    "book_name": "$BOOK_NAME_ESC",
    "book_numbering": ${BOOK_NUMBERING:-0},
    "book_visible": ${BOOK_VISIBLE:-0},
    "chapters": $CHAPTERS_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_book_result.json

echo ""
echo "Result JSON preview:"
head -n 20 /tmp/create_book_result.json
echo "..."
echo "=== Export Complete ==="
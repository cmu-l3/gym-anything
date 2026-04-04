#!/bin/bash
# export_result.sh - Post-task hook for gutenberg_course_readings

echo "=== Exporting Gutenberg Task Results ==="

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Prepare Variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
BASE_DIR="/home/ga/Documents/CourseTexts"
JSON_PATH="$BASE_DIR/reading_list.json"

# 3. Check Files and Directory Structure
# We verify the existence, size, timestamp, and content fingerprint of each expected file.
# Expected structure:
# - Austen/pride_and_prejudice.txt
# - Shelley/frankenstein.txt
# - Dickens/great_expectations.txt
# - Wilde/dorian_gray.txt
# - Conrad/heart_of_darkness.txt

# Helper function to check a book
check_book() {
    local relative_path="$1"
    local fingerprint="$2"
    local full_path="$BASE_DIR/$relative_path"
    
    local exists=0
    local size=0
    local fresh=0
    local content_match=0
    
    if [ -f "$full_path" ]; then
        exists=1
        size=$(stat -c %s "$full_path" 2>/dev/null || echo "0")
        mtime=$(stat -c %Y "$full_path" 2>/dev/null || echo "0")
        
        if [ "$mtime" -gt "$TASK_START" ]; then
            fresh=1
        fi
        
        # Check content fingerprint (case insensitive grep)
        if grep -qi "$fingerprint" "$full_path" 2>/dev/null; then
            content_match=1
        fi
    fi
    
    # Return JSON object for this file
    echo "{\"path\": \"$relative_path\", \"exists\": $exists, \"size\": $size, \"fresh\": $fresh, \"content_match\": $content_match}"
}

echo "Checking book files..."
FILE_1=$(check_book "Austen/pride_and_prejudice.txt" "Truth universally acknowledged")
FILE_2=$(check_book "Shelley/frankenstein.txt" "Frankenstein")
FILE_3=$(check_book "Dickens/great_expectations.txt" "Pirrip")
FILE_4=$(check_book "Wilde/dorian_gray.txt" "Dorian")
FILE_5=$(check_book "Conrad/heart_of_darkness.txt" "Nellie")

# 4. Check Reading List JSON
JSON_EXISTS=0
JSON_VALID=0
JSON_CONTENT=""

if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS=1
    # Validate JSON syntax using python
    if python3 -c "import json; json.load(open('$JSON_PATH'))" 2>/dev/null; then
        JSON_VALID=1
        # Read content to embed in result
        JSON_CONTENT=$(cat "$JSON_PATH")
    else
        JSON_CONTENT="{}"
    fi
else
    JSON_CONTENT="{}"
fi

# 5. Check Firefox History and Bookmarks
# Kill Firefox to flush WAL
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
# Fallback logic if temp file missing
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

GUTENBERG_VISITS=0
COURSE_FOLDER_EXISTS=0
COURSE_FOLDER_COUNT=0
COURSE_BOOKMARKS_VALID=0

if [ -f "$PLACES_DB" ]; then
    # Snapshot DB
    cp "$PLACES_DB" /tmp/places_snapshot.sqlite 2>/dev/null
    
    # Check History (Visits to gutenberg.org after task start)
    GUTENBERG_VISITS=$(sqlite3 /tmp/places_snapshot.sqlite \
        "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%gutenberg.org%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
         
    # Check Bookmark Folder "Course Readings"
    FOLDER_ID=$(sqlite3 /tmp/places_snapshot.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE 'Course Readings' LIMIT 1;" 2>/dev/null || echo "")
        
    if [ -n "$FOLDER_ID" ]; then
        COURSE_FOLDER_EXISTS=1
        
        # Count bookmarks in this folder
        COURSE_FOLDER_COUNT=$(sqlite3 /tmp/places_snapshot.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
            
        # Check if bookmarks are actually for Gutenberg
        COURSE_BOOKMARKS_VALID=$(sqlite3 /tmp/places_snapshot.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id \
             WHERE b.parent=${FOLDER_ID} AND b.type=1 AND p.url LIKE '%gutenberg.org%';" 2>/dev/null || echo "0")
    fi
    
    rm -f /tmp/places_snapshot.sqlite
fi

# 6. Construct Final Result JSON
# Using python to safely construct JSON to avoid string escaping issues
python3 << EOF
import json
import sys

result = {
    "task_start_timestamp": $TASK_START,
    "files": [
        $FILE_1,
        $FILE_2,
        $FILE_3,
        $FILE_4,
        $FILE_5
    ],
    "json_file": {
        "exists": bool($JSON_EXISTS),
        "valid": bool($JSON_VALID),
        "content": $JSON_CONTENT
    },
    "browser_data": {
        "gutenberg_visits": int($GUTENBERG_VISITS),
        "bookmark_folder_exists": bool($COURSE_FOLDER_EXISTS),
        "bookmark_count": int($COURSE_FOLDER_COUNT),
        "valid_gutenberg_bookmarks": int($COURSE_BOOKMARKS_VALID)
    }
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

# Ensure permissions
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
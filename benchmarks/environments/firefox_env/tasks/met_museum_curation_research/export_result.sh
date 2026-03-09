#!/bin/bash
# export_result.sh - Post-task hook for met_museum_curation_research

echo "=== Exporting Met Museum Curation Results ==="

# 1. Final Screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to flush SQLite WAL (Write Ahead Log) to the main database file
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read Metadata
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Verify Catalog JSON File
CATALOG_PATH="/home/ga/Documents/exhibition_catalog.json"
CATALOG_EXISTS="false"
CATALOG_VALID="false"
CATALOG_CONTENT="[]"

if [ -f "$CATALOG_PATH" ]; then
    CATALOG_EXISTS="true"
    # Validate JSON syntax and content using python
    CATALOG_CONTENT=$(cat "$CATALOG_PATH")
    CATALOG_VALID=$(python3 -c "import json, sys; 
try: 
    json.load(open('$CATALOG_PATH'))
    print('true')
except: 
    print('false')" 2>/dev/null || echo "false")
fi

# 5. Verify Image Download
IMAGES_DIR="/home/ga/Documents/met_images"
IMAGE_FOUND="false"
IMAGE_SIZE=0
IMAGE_FILENAME=""

# Find the largest file in the directory that was modified/created after task start
if [ -d "$IMAGES_DIR" ]; then
    # Find files newer than task start
    LARGEST_IMG=$(find "$IMAGES_DIR" -type f -newermt "@$TASK_START" -printf "%s %p\n" | sort -nr | head -1 | cut -d' ' -f2-)
    
    if [ -n "$LARGEST_IMG" ]; then
        IMAGE_FOUND="true"
        IMAGE_FILENAME=$(basename "$LARGEST_IMG")
        IMAGE_SIZE=$(stat -c %s "$LARGEST_IMG")
    fi
fi

# 6. Verify Bookmarks
BOOKMARK_FOLDER_FOUND="false"
BOOKMARK_COUNT=0
BOOKMARK_URLS="[]"

if [ -f "$PLACES_DB" ]; then
    # Checkpoint WAL
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    # Check for 'Met Van Gogh' folder (case-insensitive)
    FOLDER_ID=$(sqlite3 "$TEMP_DB" "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title)='met van gogh' LIMIT 1;" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_FOUND="true"
        
        # Get count of bookmarks in that folder
        BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=$FOLDER_ID;" 2>/dev/null || echo "0")
        
        # Get URLs of those bookmarks
        URLS=$(sqlite3 "$TEMP_DB" "
            SELECT p.url 
            FROM moz_bookmarks b 
            JOIN moz_places p ON b.fk = p.id 
            WHERE b.type=1 AND b.parent=$FOLDER_ID;" 2>/dev/null)
            
        # Format as JSON array string
        BOOKMARK_URLS=$(echo "$URLS" | python3 -c "import sys, json; print(json.dumps([l.strip() for l in sys.stdin]))")
    fi
    
    rm -f "$TEMP_DB"
fi

# 7. Create Result JSON
# Use Python to reliably construct JSON to avoid escaping hell in bash
python3 <<EOF > /tmp/met_curation_result.json
import json
import os

result = {
    "task_start_ts": $TASK_START,
    "catalog": {
        "exists": $CATALOG_EXISTS,
        "valid_json": $CATALOG_VALID,
        "content_raw": """$CATALOG_CONTENT"""
    },
    "image": {
        "found": $IMAGE_FOUND,
        "filename": "$IMAGE_FILENAME",
        "size_bytes": $IMAGE_SIZE
    },
    "bookmarks": {
        "folder_found": $BOOKMARK_FOLDER_FOUND,
        "count": $BOOKMARK_COUNT,
        "urls": $BOOKMARK_URLS
    }
}

with open('/tmp/met_curation_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Ensure permissions
chmod 666 /tmp/met_curation_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/met_curation_result.json
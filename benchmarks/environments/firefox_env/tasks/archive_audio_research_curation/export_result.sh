#!/bin/bash
# export_result.sh - Post-task hook for archive_audio_research_curation

echo "=== Exporting archive_audio_research_curation results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Prepare result variables
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

TARGET_DIR="/home/ga/Documents/FDR_Audio"
MANIFEST_FILE="$TARGET_DIR/manifest.json"

# 3. Analyze File System State
FOLDER_EXISTS="false"
MP3_COUNT=0
MP3_FILES_JSON="[]"
MANIFEST_EXISTS="false"
MANIFEST_CONTENT="null"

if [ -d "$TARGET_DIR" ]; then
    FOLDER_EXISTS="true"
    
    # Count MP3s and gather details
    # We look for files > 500KB to filter out empty downloads/broken links
    # Using python to create a clean JSON array of file info
    MP3_FILES_JSON=$(python3 -c "
import os, json
files = []
try:
    for f in os.listdir('$TARGET_DIR'):
        if f.lower().endswith('.mp3'):
            path = os.path.join('$TARGET_DIR', f)
            stat = os.stat(path)
            files.append({
                'name': f,
                'size': stat.st_size,
                'mtime': stat.st_mtime
            })
    print(json.dumps(files))
except Exception as e:
    print('[]')
")
    
    MP3_COUNT=$(echo "$MP3_FILES_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
    
    # Check Manifest
    if [ -f "$MANIFEST_FILE" ]; then
        MANIFEST_EXISTS="true"
        # Read content if it's valid JSON
        if python3 -c "import json, sys; json.load(open('$MANIFEST_FILE'))" 2>/dev/null; then
            MANIFEST_CONTENT=$(cat "$MANIFEST_FILE")
        else
            MANIFEST_CONTENT="\"INVALID_JSON\""
        fi
    fi
fi

# 4. Analyze Firefox History (Archive.org visits)
ARCHIVE_VISITS=0
ITEM_PAGE_VISITS=0

# Kill Firefox to flush WAL
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
# Fallback if profile path wasn't saved correctly
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
     PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    PLACES_DB="$PROFILE_DIR/places.sqlite"
    # Copy DB to temp to avoid lock
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    # Count general archive.org visits
    ARCHIVE_VISITS=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%archive.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Count specific item details pages (stronger evidence of searching)
    ITEM_PAGE_VISITS=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%archive.org/details/%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    rm -f "$TEMP_DB"
fi

# 5. Create Result JSON
# Use a temp file to avoid quoting issues
TEMP_RESULT=$(mktemp)

cat > "$TEMP_RESULT" << EOF
{
  "folder_exists": $FOLDER_EXISTS,
  "mp3_count": $MP3_COUNT,
  "mp3_files": $MP3_FILES_JSON,
  "manifest_exists": $MANIFEST_EXISTS,
  "manifest_content": $MANIFEST_CONTENT,
  "archive_visits": $ARCHIVE_VISITS,
  "item_page_visits": $ITEM_PAGE_VISITS,
  "task_start_time": $TASK_START
}
EOF

# Move to final location
cp "$TEMP_RESULT" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_RESULT"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
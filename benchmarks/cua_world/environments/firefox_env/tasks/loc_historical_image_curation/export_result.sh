#!/bin/bash
# export_result.sh - Post-task hook for loc_historical_image_curation

echo "=== Exporting loc_historical_image_curation results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Kill Firefox to flush database WAL (Write Ahead Log)
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

# Basic variables
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
TARGET_DIR="/home/ga/Documents/curated_images"
CREDITS_FILE="$TARGET_DIR/credits.json"

# --- 1. File Verification ---
echo "Verifying files in $TARGET_DIR..."

FILES_JSON="[]"
DIR_EXISTS="false"

if [ -d "$TARGET_DIR" ]; then
    DIR_EXISTS="true"
    # Create a temporary python script to list files and sizes as JSON
    cat > /tmp/list_files.py << PYEOF
import os
import json
import time

target_dir = "$TARGET_DIR"
task_start = $TASK_START
files = []

if os.path.exists(target_dir):
    for f in os.listdir(target_dir):
        path = os.path.join(target_dir, f)
        if os.path.isfile(path) and f != "credits.json":
            stat = os.stat(path)
            # Only count files modified/created after task start
            if stat.st_mtime > task_start:
                files.append({
                    "name": f,
                    "size_bytes": stat.st_size,
                    "mtime": stat.st_mtime
                })

print(json.dumps(files))
PYEOF
    FILES_JSON=$(python3 /tmp/list_files.py)
    rm -f /tmp/list_files.py
fi

# --- 2. Credits JSON Verification ---
CREDITS_CONTENT="null"
CREDITS_EXISTS="false"
CREDITS_VALID="false"

if [ -f "$CREDITS_FILE" ]; then
    CREDITS_EXISTS="true"
    # Validate JSON
    if python3 -m json.tool "$CREDITS_FILE" > /dev/null 2>&1; then
        CREDITS_VALID="true"
        CREDITS_CONTENT=$(cat "$CREDITS_FILE")
    fi
fi

# --- 3. Browser History Verification ---
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
LOC_VISITS=0
ITEM_VISITS=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    PLACES_DB="$PROFILE_DIR/places.sqlite"
    # Copy DB to avoid lock issues
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Count visits to loc.gov
        LOC_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%loc.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        
        # Count visits to specific item pages (indicating deep research)
        ITEM_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%loc.gov/item/%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        rm -f "$TEMP_DB"
    fi
fi

# --- 4. Create Result JSON ---
RESULT_JSON_PATH="/tmp/loc_curation_result.json"
cat > /tmp/create_result.py << PYEOF
import json
import os

result = {
    "task_start": $TASK_START,
    "dir_exists": $DIR_EXISTS,
    "downloaded_files": $FILES_JSON,
    "credits_exists": $CREDITS_EXISTS,
    "credits_valid": $CREDITS_VALID,
    "credits_content": $CREDITS_CONTENT,
    "loc_visits": $LOC_VISITS,
    "item_visits": $ITEM_VISITS
}

with open("$RESULT_JSON_PATH", "w") as f:
    json.dump(result, f)
PYEOF

python3 /tmp/create_result.py
rm -f /tmp/create_result.py

echo "Export complete. Result saved to $RESULT_JSON_PATH"
cat "$RESULT_JSON_PATH"
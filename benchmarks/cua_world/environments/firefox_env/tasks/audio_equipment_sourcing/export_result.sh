#!/bin/bash
# export_result.sh - Post-task hook for audio_equipment_sourcing

echo "=== Exporting Audio Equipment Sourcing Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to flush database WAL (Write-Ahead Log)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load configuration
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Analyze Firefox History & Bookmarks
VISIT_SHURE=0
VISIT_NEUMANN=0
VISIT_AT=0
FOLDER_EXISTS=0
FOLDER_BOOKMARK_COUNT=0

if [ -f "$PLACES_DB" ]; then
    # Checkpoint WAL to ensure data is in main DB
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check History (Official domains only)
        VISIT_SHURE=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%shure.com%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
             
        VISIT_NEUMANN=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%neumann.com%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
             
        VISIT_AT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%audio-technica.com%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

        # Check Bookmarks
        # Find folder ID for "Studio Tech Specs"
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE 'Studio Tech Specs' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            FOLDER_EXISTS=1
            # Count bookmarks in that folder
            FOLDER_BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 5. Analyze Downloads
# Count PDFs downloaded AFTER task start with size > 50KB (avoid empty/corrupt files)
PDF_COUNT=0
DOWNLOADS_DIR="/home/ga/Downloads"
if [ -d "$DOWNLOADS_DIR" ]; then
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            FSIZE=$(stat -c%s "$file")
            # 50KB = 51200 bytes
            if [ "$FSIZE" -gt 51200 ]; then
                PDF_COUNT=$((PDF_COUNT + 1))
            fi
        fi
    done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -name "*.pdf" -newermt "@$TASK_START")
fi

# 6. Analyze Output JSON
JSON_FILE="/home/ga/Documents/mic_specs.json"
JSON_EXISTS=0
JSON_FRESH=0
JSON_CONTENT="{}"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_FRESH=1
    fi
    # Read content safely
    JSON_CONTENT=$(cat "$JSON_FILE")
fi

# 7. Create Verification JSON
OUTPUT_JSON="/tmp/task_result.json"
cat > "$OUTPUT_JSON" <<EOF
{
  "task_start": $TASK_START,
  "history": {
    "shure": $VISIT_SHURE,
    "neumann": $VISIT_NEUMANN,
    "audio_technica": $VISIT_AT
  },
  "bookmarks": {
    "folder_exists": $FOLDER_EXISTS,
    "count": $FOLDER_BOOKMARK_COUNT
  },
  "downloads": {
    "pdf_count": $PDF_COUNT
  },
  "output_file": {
    "exists": $JSON_EXISTS,
    "fresh": $JSON_FRESH
  }
}
EOF

# Note: The JSON content is handled by verifier.py reading the file directly 
# via copy_from_env to avoid escaping issues in shell script

# Set permissions
chmod 644 "$OUTPUT_JSON"

echo "Export complete. Result saved to $OUTPUT_JSON"
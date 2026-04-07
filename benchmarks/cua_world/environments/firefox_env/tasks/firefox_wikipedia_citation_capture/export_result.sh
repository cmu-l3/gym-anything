#!/bin/bash
echo "=== Exporting task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Copy SQLite DB to safely query without lock conflicts
cp /home/ga/.mozilla/firefox/default.profile/places.sqlite /tmp/places_copy.sqlite 2>/dev/null || true

# 1. Query Browser History for Wikipedia Apollo 11 visit
HISTORY_VISITED="false"
if sqlite3 /tmp/places_copy.sqlite "SELECT p.url FROM moz_historyvisits h JOIN moz_places p ON h.place_id = p.id;" | grep -qi "wikipedia.org/wiki/Apollo_11"; then
    HISTORY_VISITED="true"
fi

# 2. Query Downloads database for any "Apollo" or "Wikipedia" files handled natively
DOWNLOADS_HANDLED="false"
if sqlite3 /tmp/places_copy.sqlite "SELECT a.content FROM moz_annos a JOIN moz_anno_attributes n ON a.anno_attribute_id = n.id WHERE n.name = 'downloads/destinationFileName';" | grep -qiE "apollo|wikipedia"; then
    DOWNLOADS_HANDLED="true"
fi

# 3. Query Bookmark Folders and Bookmarks
# Use jq to safely serialize the command outputs into JSON arrays
FOLDERS_JSON=$(sqlite3 /tmp/places_copy.sqlite "SELECT title FROM moz_bookmarks WHERE type = 2;" 2>/dev/null | jq -R -s -c 'split("\n")[:-1]' || echo "[]")
BOOKMARKS_JSON=$(sqlite3 /tmp/places_copy.sqlite "SELECT parent.title || '|' || b.title || '|' || p.url FROM moz_bookmarks b JOIN moz_bookmarks parent ON b.parent = parent.id JOIN moz_places p ON b.fk = p.id WHERE b.type = 1;" 2>/dev/null | jq -R -s -c 'split("\n")[:-1]' || echo "[]")

# 4. Analyze PDF output
PDF_PATH="/home/ga/Documents/Research/apollo11.pdf"
PDF_EXISTS="false"
PDF_SIZE="0"
PDF_IS_VALID="false"
PDF_MTIME="0"

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c%s "$PDF_PATH" 2>/dev/null || echo "0")
    PDF_MTIME=$(stat -c%Y "$PDF_PATH" 2>/dev/null || echo "0")
    
    # Check for PDF magic bytes to prove it's actually a PDF and not a blank file
    if head -c 10 "$PDF_PATH" | grep -q "PDF"; then
        PDF_IS_VALID="true"
    fi
fi

# 5. Analyze BibTeX output
BIB_PATH="/home/ga/Documents/Research/apollo11.bib"
BIB_EXISTS="false"
BIB_CONTENT='""'
BIB_MTIME="0"

if [ -f "$BIB_PATH" ]; then
    BIB_EXISTS="true"
    BIB_MTIME=$(stat -c%Y "$BIB_PATH" 2>/dev/null || echo "0")
    # Grab the first 20 lines of the BibTeX to verify content inside Python
    BIB_CONTENT=$(head -n 20 "$BIB_PATH" 2>/dev/null | jq -R -s -c '.' || echo '""')
fi

# Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "history_visited_wiki": $HISTORY_VISITED,
    "downloads_handled": $DOWNLOADS_HANDLED,
    "folders": $FOLDERS_JSON,
    "bookmarks": $BOOKMARKS_JSON,
    "pdf": {
        "exists": $PDF_EXISTS,
        "size": $PDF_SIZE,
        "is_valid": $PDF_IS_VALID,
        "mtime": $PDF_MTIME
    },
    "bib": {
        "exists": $BIB_EXISTS,
        "content": $BIB_CONTENT,
        "mtime": $BIB_MTIME
    }
}
EOF

# Ensure proper permissions and location for the framework to read
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
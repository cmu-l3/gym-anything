#!/bin/bash
echo "=== Exporting Linguistic Localization Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract SQLite Web Data for search engine verification before closing (to avoid locked DBs)
cp "/home/ga/.config/google-chrome/Default/Web Data" "/tmp/WebData_copy" 2>/dev/null || true
sqlite3 "/tmp/WebData_copy" "SELECT keyword, url FROM keywords;" > /tmp/search_engines.txt 2>/dev/null || true
chmod 666 /tmp/search_engines.txt 2>/dev/null || true

# 3. Gracefully close Chrome to flush Preferences and Bookmarks to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 4. Check for downloaded files
TMX_PATH="/home/ga/Documents/Project_Alpha/project_alpha_es.tmx"
PDF_PATH="/home/ga/Documents/Project_Alpha/medical_style_guide.pdf"

TMX_EXISTS="false"
PDF_EXISTS="false"
TMX_CREATED_DURING="false"
PDF_CREATED_DURING="false"

if [ -f "$TMX_PATH" ]; then
    TMX_EXISTS="true"
    MTIME=$(stat -c %Y "$TMX_PATH")
    if [ "$MTIME" -ge "$TASK_START" ]; then TMX_CREATED_DURING="true"; fi
fi

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    MTIME=$(stat -c %Y "$PDF_PATH")
    if [ "$MTIME" -ge "$TASK_START" ]; then PDF_CREATED_DURING="true"; fi
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "tmx_exists": $TMX_EXISTS,
    "pdf_exists": $PDF_EXISTS,
    "tmx_created_during_task": $TMX_CREATED_DURING,
    "pdf_created_during_task": $PDF_CREATED_DURING
}
EOF

mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
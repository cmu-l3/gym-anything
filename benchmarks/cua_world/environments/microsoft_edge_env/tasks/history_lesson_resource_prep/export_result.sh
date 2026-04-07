#!/bin/bash
# export_result.sh - Post-task hook for history_lesson_resource_prep

echo "=== Exporting task results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check for Downloaded High-Res Image
# We look for files in ~/Downloads that are reasonably large (e.g., > 1MB) and created after task start
DOWNLOAD_FOUND="false"
DOWNLOAD_FILENAME=""
DOWNLOAD_SIZE=0

# Loop through files in downloads
for f in /home/ga/Downloads/*; do
    if [ -f "$f" ]; then
        fsize=$(stat -c %s "$f")
        fmtime=$(stat -c %Y "$f")
        
        # Check if modified after start and size > 500KB (allow some variance, but high res should be big)
        if [ "$fmtime" -gt "$TASK_START" ] && [ "$fsize" -gt 500000 ]; then
            DOWNLOAD_FOUND="true"
            DOWNLOAD_FILENAME=$(basename "$f")
            DOWNLOAD_SIZE=$fsize
            # If we find a JPG or PDF, prioritize it, otherwise take the first match
            if [[ "$f" == *.jpg ]] || [[ "$f" == *.pdf ]]; then
                break
            fi
        fi
    fi
done

# 4. Check Bookmark
# We verify if a bookmark pointing to archives.gov exists
BOOKMARKS_FILE="/home/ga/.config/microsoft-edge/Default/Bookmarks"
BOOKMARK_FOUND="false"
BOOKMARK_TITLE=""
BOOKMARK_URL=""

if [ -f "$BOOKMARKS_FILE" ]; then
    # Use python to parse JSON safely
    BOOKMARK_INFO=$(python3 << 'PYEOF'
import json, sys
try:
    with open("/home/ga/.config/microsoft-edge/Default/Bookmarks", "r") as f:
        data = json.load(f)
    
    def find_bookmark(node):
        if node.get("type") == "url":
            url = node.get("url", "").lower()
            if "archives.gov" in url:
                return {"found": True, "title": node.get("name"), "url": node.get("url")}
        
        if node.get("type") == "folder":
            for child in node.get("children", []):
                res = find_bookmark(child)
                if res: return res
        return None

    roots = data.get("roots", {})
    found = None
    for key in roots:
        found = find_bookmark(roots[key])
        if found: break
    
    if found:
        print(json.dumps(found))
    else:
        print(json.dumps({"found": False}))
except Exception as e:
    print(json.dumps({"found": False, "error": str(e)}))
PYEOF
    )
    
    BOOKMARK_FOUND=$(echo "$BOOKMARK_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('found'))")
    BOOKMARK_TITLE=$(echo "$BOOKMARK_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('title', ''))")
    BOOKMARK_URL=$(echo "$BOOKMARK_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('url', ''))")
fi

# 5. Check Worksheet File
WORKSHEET_PATH="/home/ga/Documents/amendment_worksheet.txt"
WORKSHEET_EXISTS="false"
WORKSHEET_CONTENT=""
WORKSHEET_CREATED_DURING="false"

if [ -f "$WORKSHEET_PATH" ]; then
    WORKSHEET_EXISTS="true"
    wmtime=$(stat -c %Y "$WORKSHEET_PATH")
    if [ "$wmtime" -gt "$TASK_START" ]; then
        WORKSHEET_CREATED_DURING="true"
    fi
    # Read content (limit size to avoid huge logs)
    WORKSHEET_CONTENT=$(head -c 5000 "$WORKSHEET_PATH")
fi

# 6. Check Browser History (Verification of navigation)
# We can't query SQLite easily while browser is open (locked), so we rely on artifacts above
# or use VLM. We'll skip raw SQLite dump here to avoid complexity/locks, 
# relying on the side effects (download, bookmark).

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "download": {
        "found": $DOWNLOAD_FOUND,
        "filename": "$DOWNLOAD_FILENAME",
        "size_bytes": $DOWNLOAD_SIZE
    },
    "bookmark": {
        "found": $BOOKMARK_FOUND,
        "title": "$BOOKMARK_TITLE",
        "url": "$BOOKMARK_URL"
    },
    "worksheet": {
        "exists": $WORKSHEET_EXISTS,
        "created_during_task": $WORKSHEET_CREATED_DURING,
        "path": "$WORKSHEET_PATH",
        "content_preview": $(python3 -c "import json, sys; print(json.dumps(sys.argv[1]))" "$WORKSHEET_CONTENT")
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
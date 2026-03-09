#!/bin/bash
echo "=== Exporting assign_colored_tags result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DB_PATH="/home/ga/Zotero/zotero.sqlite"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query 'settings' table for 'tagColors'
# This returns a JSON string like: [{"name":"tag1","color":"#F00"}, ...]
TAG_COLORS_JSON=$(sqlite3 "$DB_PATH" "SELECT value FROM settings WHERE setting='tagColors' AND libraryID=1;" 2>/dev/null || echo "[]")

# If empty, default to empty array
if [ -z "$TAG_COLORS_JSON" ]; then
    TAG_COLORS_JSON="[]"
fi

# 3. Verify tags still exist and have items (Anti-gaming check)
# Returns line format: "tag_name|item_count"
TAG_STATS=$(sqlite3 "$DB_PATH" <<EOF
SELECT t.name, COUNT(it.itemID) 
FROM tags t 
LEFT JOIN itemTags it ON t.tagID = it.tagID 
WHERE t.name IN ('deep-learning', 'foundational', 'computer-vision', 'NLP')
GROUP BY t.name;
EOF
)

# Convert SQL output to JSON array for tag stats
TAG_STATS_JSON="["
while IFS='|' read -r name count; do
    TAG_STATS_JSON+="{\"name\":\"$name\",\"count\":$count},"
done <<< "$TAG_STATS"
# Remove trailing comma and close array
TAG_STATS_JSON="${TAG_STATS_JSON%,}]"
if [ "$TAG_STATS_JSON" == "]" ]; then TAG_STATS_JSON="[]"; fi

# 4. Check if App is running
APP_RUNNING=$(pgrep -f "zotero" > /dev/null && echo "true" || echo "false")

# 5. Construct Result JSON
# We treat the SQLite JSON string as a raw string to be parsed by Python
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "tag_colors_setting": $TAG_COLORS_JSON,
    "tag_stats": $TAG_STATS_JSON,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
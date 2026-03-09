#!/bin/bash
echo "=== Exporting create_saved_search results ==="
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_saved_search_count.txt 2>/dev/null || echo "0")

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Find DB
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Database not found"
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

# Query current saved search count
CURRENT_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM savedSearches" 2>/dev/null || echo "0")

# Find the most recently created saved search (assuming ID increments)
# We look for ANY search created, but prioritize one with relevant keywords if multiple exist
SEARCH_INFO=$(sqlite3 "$JURISM_DB" "SELECT savedSearchID, savedSearchName FROM savedSearches ORDER BY savedSearchID DESC LIMIT 1" 2>/dev/null)

SEARCH_ID=""
SEARCH_NAME=""
CONDITIONS_JSON="[]"

if [ -n "$SEARCH_INFO" ]; then
    SEARCH_ID=$(echo "$SEARCH_INFO" | cut -d'|' -f1)
    SEARCH_NAME=$(echo "$SEARCH_INFO" | cut -d'|' -f2)
    
    # Extract conditions for this search
    # Format: field | operator | value
    # We use python to format this into JSON directly to handle escaping safely
    CONDITIONS_JSON=$(python3 -c "
import sqlite3
import json

try:
    conn = sqlite3.connect('$JURISM_DB')
    c = conn.cursor()
    c.execute('''
        SELECT field, operator, value 
        FROM savedSearchConditions 
        WHERE savedSearchID = ?
    ''', ($SEARCH_ID,))
    
    rows = c.fetchall()
    conditions = [{'field': r[0], 'operator': r[1], 'value': r[2]} for r in rows]
    print(json.dumps(conditions))
    conn.close()
except:
    print('[]')
")
fi

# Check if application is running
APP_RUNNING=$(pgrep -f "jurism" > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "app_running": $APP_RUNNING,
    "search_found": $([ -n "$SEARCH_ID" ] && echo "true" || echo "false"),
    "search_id": "${SEARCH_ID:-0}",
    "search_name": "$(echo "$SEARCH_NAME" | sed 's/"/\\"/g')",
    "conditions": $CONDITIONS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json
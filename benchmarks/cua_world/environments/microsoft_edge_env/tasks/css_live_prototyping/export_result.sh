#!/bin/bash
# Export script for CSS Live Prototyping task

echo "=== Exporting css_live_prototyping results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MOCKUP_PATH="/home/ga/Desktop/mockup.png"
CSS_PATH="/home/ga/Desktop/new_styles.css"

# 1. Take final system screenshot (what the agent sees at the very end)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Mockup Screenshot File
MOCKUP_EXISTS="false"
MOCKUP_CREATED_DURING="false"
MOCKUP_SIZE=0

if [ -f "$MOCKUP_PATH" ]; then
    MOCKUP_EXISTS="true"
    MOCKUP_SIZE=$(stat -c %s "$MOCKUP_PATH" 2>/dev/null || echo "0")
    MOCKUP_MTIME=$(stat -c %Y "$MOCKUP_PATH" 2>/dev/null || echo "0")
    
    if [ "$MOCKUP_MTIME" -gt "$TASK_START" ]; then
        MOCKUP_CREATED_DURING="true"
    fi
    
    # Copy for verification
    cp "$MOCKUP_PATH" /tmp/agent_mockup.png
fi

# 3. Check CSS File
CSS_EXISTS="false"
CSS_CREATED_DURING="false"
CSS_CONTENT=""

if [ -f "$CSS_PATH" ]; then
    CSS_EXISTS="true"
    CSS_MTIME=$(stat -c %Y "$CSS_PATH" 2>/dev/null || echo "0")
    
    if [ "$CSS_MTIME" -gt "$TASK_START" ]; then
        CSS_CREATED_DURING="true"
    fi
    
    # Read content safely (limit size to prevent massive JSON)
    CSS_CONTENT=$(head -c 5000 "$CSS_PATH")
fi

# 4. Check Browser History for example.com
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
VISITED_EXAMPLE="false"

if [ -f "$HISTORY_DB" ]; then
    # We copy to temp to avoid lock issues
    cp "$HISTORY_DB" /tmp/history_final.db
    
    # Python script to query sqlite
    VISITED_EXAMPLE=$(python3 << 'PY_EOF'
import sqlite3
import sys

try:
    conn = sqlite3.connect('/tmp/history_final.db')
    cursor = conn.cursor()
    # Check for recent visits to example.com
    # Timestamps in chrome/edge history are microseconds since 1601-01-01
    # We'll just check if it exists in urls table, simpler than timestamp math here
    # since we cleared history/started fresh or just look for existence
    cursor.execute("SELECT count(*) FROM urls WHERE url LIKE '%example.com%'")
    count = cursor.fetchone()[0]
    print("true" if count > 0 else "false")
    conn.close()
except Exception as e:
    print("false")
PY_EOF
)
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "mockup_file": {
        "exists": $MOCKUP_EXISTS,
        "created_during_task": $MOCKUP_CREATED_DURING,
        "size_bytes": $MOCKUP_SIZE,
        "path_for_verification": "/tmp/agent_mockup.png"
    },
    "css_file": {
        "exists": $CSS_EXISTS,
        "created_during_task": $CSS_CREATED_DURING,
        "content": $(echo "$CSS_CONTENT" | jq -R s)
    },
    "history": {
        "visited_example_com": $VISITED_EXAMPLE
    },
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move and chmod
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
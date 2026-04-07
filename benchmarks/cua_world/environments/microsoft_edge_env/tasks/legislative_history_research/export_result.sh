#!/bin/bash
# Export results for Legislative History Research task

echo "=== Exporting Results ==="

# 1. Capture final state
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define paths
PDF_PATH="/home/ga/Documents/Legislation/chips_act_final.pdf"
TALLY_PATH="/home/ga/Documents/Legislation/vote_tally.txt"

# 3. Analyze PDF output
PDF_EXISTS="false"
PDF_SIZE="0"
PDF_CREATED_DURING_TASK="false"

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH")
    PDF_MTIME=$(stat -c %Y "$PDF_PATH")
    
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_CREATED_DURING_TASK="true"
    fi
fi

# 4. Analyze Text output
TALLY_EXISTS="false"
TALLY_CREATED_DURING_TASK="false"
TALLY_CONTENT=""

if [ -f "$TALLY_PATH" ]; then
    TALLY_EXISTS="true"
    TALLY_MTIME=$(stat -c %Y "$TALLY_PATH")
    
    if [ "$TALLY_MTIME" -gt "$TASK_START" ]; then
        TALLY_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely (limit size)
    TALLY_CONTENT=$(head -c 1000 "$TALLY_PATH")
fi

# 5. Check Browser History
INITIAL_VISITS=$(cat /tmp/initial_congress_visits.txt 2>/dev/null || echo "0")
CURRENT_VISITS=$(sqlite3 /home/ga/.config/microsoft-edge/Default/History "SELECT COUNT(*) FROM urls WHERE url LIKE '%congress.gov%';" 2>/dev/null || echo "0")
VISITED_CONGRESS="false"

if [ "$CURRENT_VISITS" -gt "$INITIAL_VISITS" ]; then
    VISITED_CONGRESS="true"
fi

# 6. Create JSON result
# Note: We use Python to write JSON to handle escaping correctly
python3 << EOF
import json
import sys

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pdf_info": {
        "exists": $PDF_EXISTS,
        "size_bytes": $PDF_SIZE,
        "created_during_task": $PDF_CREATED_DURING_TASK,
        "path": "$PDF_PATH"
    },
    "tally_info": {
        "exists": $TALLY_EXISTS,
        "created_during_task": $TALLY_CREATED_DURING_TASK,
        "content_preview": """$TALLY_CONTENT""",
        "path": "$TALLY_PATH"
    },
    "browser_history": {
        "visited_congress_gov": $VISITED_CONGRESS
    },
    "screenshot_path": "/tmp/task_final.png"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
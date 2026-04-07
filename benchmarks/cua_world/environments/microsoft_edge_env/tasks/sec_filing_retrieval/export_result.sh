#!/bin/bash
# Export script for SEC Filing Retrieval task

echo "=== Exporting results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOCS_DIR="/home/ga/Documents"
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check for downloaded filing (PDF or HTML)
# Look for files > 1MB (10-Ks are large) created after task start
DOWNLOADED_FILE=""
DOWNLOAD_SIZE=0
DOWNLOAD_TIMESTAMP=0

# Find largest file in Documents
LARGEST_FILE=$(find "$DOCS_DIR" -type f -printf "%s %p\n" | sort -rn | head -n1 | cut -d' ' -f2-)

if [ -n "$LARGEST_FILE" ]; then
    SIZE=$(stat -c %s "$LARGEST_FILE")
    M_TIME=$(stat -c %Y "$LARGEST_FILE")
    FILENAME=$(basename "$LARGEST_FILE")
    
    # Check if modified after start
    if [ "$M_TIME" -gt "$TASK_START" ]; then
        DOWNLOADED_FILE="$FILENAME"
        DOWNLOAD_SIZE="$SIZE"
        DOWNLOAD_TIMESTAMP="$M_TIME"
    fi
fi

# 3. Read the summary text file
SUMMARY_FILE="$DOCS_DIR/key_financials.txt"
SUMMARY_EXISTS="false"
SUMMARY_CONTENT=""
SUMMARY_TIMESTAMP=0

if [ -f "$SUMMARY_FILE" ]; then
    S_TIME=$(stat -c %Y "$SUMMARY_FILE")
    if [ "$S_TIME" -gt "$TASK_START" ]; then
        SUMMARY_EXISTS="true"
        SUMMARY_TIMESTAMP="$S_TIME"
        SUMMARY_CONTENT=$(cat "$SUMMARY_FILE" | head -c 1000) # Limit size
    fi
fi

# 4. Check Browser History for SEC visits
# Copy history DB to tmp to avoid locks
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
TEMP_HISTORY="/tmp/history_check.sqlite"
SEC_VISITS=0

if [ -f "$HISTORY_DB" ]; then
    cp "$HISTORY_DB" "$TEMP_HISTORY"
    # Query visits to sec.gov after task start (converted to webkit timestamp)
    # Webkit epoch is 1601-01-01. Unix epoch is 1970-01-01. Difference is 11644473600 seconds.
    # Timestamps in DB are microseconds.
    
    # Simple check: just look for URL match, rely on task constraints for timing
    SEC_VISITS=$(sqlite3 "$TEMP_HISTORY" "SELECT COUNT(*) FROM urls WHERE url LIKE '%sec.gov%' OR url LIKE '%edgar%';" 2>/dev/null || echo "0")
    rm -f "$TEMP_HISTORY"
fi

# 5. Create JSON result
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'download': {
        'filename': '$DOWNLOADED_FILE',
        'size_bytes': $DOWNLOAD_SIZE,
        'timestamp': $DOWNLOAD_TIMESTAMP,
        'is_large_enough': $DOWNLOAD_SIZE > 500000  # 500KB threshold
    },
    'summary': {
        'exists': $SUMMARY_EXISTS == True,
        'content': '''$SUMMARY_CONTENT''',
        'timestamp': $SUMMARY_TIMESTAMP
    },
    'history': {
        'sec_visits': $SEC_VISITS
    },
    'screenshots': {
        'initial': '/tmp/task_initial.png',
        'final': '/tmp/task_final.png'
    }
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="
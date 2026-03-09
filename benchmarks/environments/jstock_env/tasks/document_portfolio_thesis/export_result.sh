#!/bin/bash
echo "=== Exporting document_portfolio_thesis results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PORTFOLIO_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check file stats
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"
RAW_CONTENT=""
CSV_JSON="[]"

if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$PORTFOLIO_FILE")
    FILE_MTIME=$(stat -c%Y "$PORTFOLIO_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi

    # Read content for debug/logging
    RAW_CONTENT=$(cat "$PORTFOLIO_FILE" | base64 -w 0)

    # Python script to parse CSV to JSON for verification
    CSV_JSON=$(python3 -c "
import csv, json, sys
try:
    with open('$PORTFOLIO_FILE', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        print(json.dumps(rows))
except Exception as e:
    print('[]')
")
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "portfolio_data": $CSV_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. content of /tmp/task_result.json:"
cat /tmp/task_result.json
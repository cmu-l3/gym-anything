#!/bin/bash
echo "=== Exporting Reconcile Task Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PORTFOLIO_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check portfolio file status
if [ -f "$PORTFOLIO_FILE" ]; then
    PORTFOLIO_EXISTS="true"
    PORTFOLIO_MTIME=$(stat -c %Y "$PORTFOLIO_FILE" 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$PORTFOLIO_MTIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    else
        MODIFIED_DURING_TASK="false"
    fi
    
    # Read CSV content and convert to JSON array of objects
    # We use python to parse the CSV properly (handling quotes)
    PORTFOLIO_CONTENT=$(python3 -c "
import csv, json
try:
    rows = []
    with open('$PORTFOLIO_FILE', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Clean up keys (remove quotes if present in keys themselves, though csv module handles this)
            rows.append(row)
    print(json.dumps(rows))
except Exception as e:
    print('[]')
")
else
    PORTFOLIO_EXISTS="false"
    MODIFIED_DURING_TASK="false"
    PORTFOLIO_CONTENT="[]"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "portfolio_exists": $PORTFOLIO_EXISTS,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "portfolio_data": $PORTFOLIO_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
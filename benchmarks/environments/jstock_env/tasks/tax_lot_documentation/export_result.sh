#!/bin/bash
echo "=== Exporting tax_lot_documentation results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/tax_lot_report.txt"
SELL_CSV_PATH="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/sellportfolio.csv"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Analyze Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME="0"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 2000) # Limit size
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
fi

# 2. Analyze Sell Portfolio CSV (JStock data)
SELL_CSV_EXISTS="false"
SELL_CSV_CONTENT=""
SELL_CSV_MTIME="0"
if [ -f "$SELL_CSV_PATH" ]; then
    SELL_CSV_EXISTS="true"
    SELL_CSV_CONTENT=$(cat "$SELL_CSV_PATH")
    SELL_CSV_MTIME=$(stat -c %Y "$SELL_CSV_PATH" 2>/dev/null || echo "0")
fi

# 3. Check timestamps (Anti-gaming)
REPORT_CREATED_DURING_TASK="false"
if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_CREATED_DURING_TASK="true"
fi

SELL_MODIFIED_DURING_TASK="false"
if [ "$SELL_CSV_MTIME" -gt "$TASK_START" ]; then
    SELL_MODIFIED_DURING_TASK="true"
fi

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_preview": $(echo "$REPORT_CONTENT" | jq -R .),
    "sell_csv_exists": $SELL_CSV_EXISTS,
    "sell_csv_modified_during_task": $SELL_MODIFIED_DURING_TASK,
    "sell_csv_content": $(echo "$SELL_CSV_CONTENT" | jq -R .),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
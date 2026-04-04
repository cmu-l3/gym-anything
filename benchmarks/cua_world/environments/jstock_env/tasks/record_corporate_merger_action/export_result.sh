#!/bin/bash
echo "=== Exporting record_corporate_merger_action result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_final.png 2>/dev/null || true

# Define paths
PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio"
BUY_CSV="$PORTFOLIO_DIR/buyportfolio.csv"
SELL_CSV="$PORTFOLIO_DIR/sellportfolio.csv"

# Check if files exist
BUY_EXISTS="false"
SELL_EXISTS="false"
[ -f "$BUY_CSV" ] && BUY_EXISTS="true"
[ -f "$SELL_CSV" ] && SELL_EXISTS="true"

# Check timestamps to see if they were modified during task
BUY_MODIFIED="false"
SELL_MODIFIED="false"

if [ "$BUY_EXISTS" = "true" ]; then
    B_MTIME=$(stat -c %Y "$BUY_CSV")
    if [ "$B_MTIME" -gt "$TASK_START" ]; then
        BUY_MODIFIED="true"
    fi
fi

if [ "$SELL_EXISTS" = "true" ]; then
    S_MTIME=$(stat -c %Y "$SELL_CSV")
    if [ "$S_MTIME" -gt "$TASK_START" ]; then
        SELL_MODIFIED="true"
    fi
fi

# Helper to read CSV content safely into JSON string
read_csv_content() {
    if [ -f "$1" ]; then
        # cat file | python to escape json
        cat "$1" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))'
    else
        echo "null"
    fi
}

BUY_CONTENT=$(read_csv_content "$BUY_CSV")
SELL_CONTENT=$(read_csv_content "$SELL_CSV")

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "buy_csv_exists": $BUY_EXISTS,
    "sell_csv_exists": $SELL_EXISTS,
    "buy_csv_modified": $BUY_MODIFIED,
    "sell_csv_modified": $SELL_MODIFIED,
    "buy_csv_content": $BUY_CONTENT,
    "sell_csv_content": $SELL_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="
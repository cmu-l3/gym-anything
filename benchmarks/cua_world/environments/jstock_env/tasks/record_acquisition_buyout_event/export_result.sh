#!/bin/bash
echo "=== Exporting task results ==="

# 1. Define Paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
SELL_PORTFOLIO="${JSTOCK_DATA_DIR}/portfolios/My Portfolio/sellportfolio.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Capture Final Screenshot (Visual Verification)
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# 3. Check CSV File Status
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_CONTENT_BASE64=""

if [ -f "$SELL_PORTFOLIO" ]; then
    FILE_EXISTS="true"
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$SELL_PORTFOLIO" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Read file content safely (encode to base64 to handle newlines/quotes in JSON)
    FILE_CONTENT_BASE64=$(base64 -w 0 "$SELL_PORTFOLIO")
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sell_portfolio_exists": $FILE_EXISTS,
    "sell_portfolio_modified": $FILE_MODIFIED,
    "sell_portfolio_path": "$SELL_PORTFOLIO",
    "sell_portfolio_b64": "$FILE_CONTENT_BASE64",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save Result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
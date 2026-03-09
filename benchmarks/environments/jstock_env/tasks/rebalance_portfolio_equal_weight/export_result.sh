#!/bin/bash
echo "=== Exporting Rebalance Portfolio Results ==="

# Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio"
SELL_CSV="$PORTFOLIO_DIR/sellportfolio.csv"
BUY_CSV="$PORTFOLIO_DIR/buyportfolio.csv"
REPORT_FILE="/home/ga/Documents/rebalancing_report.txt"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Report File
REPORT_EXISTS=false
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -c 2000) # Limit size
fi

# 3. Analyze Sell Portfolio (Read raw lines, python verifier will parse)
SELL_CSV_CONTENT=""
if [ -f "$SELL_CSV" ]; then
    SELL_CSV_CONTENT=$(cat "$SELL_CSV")
fi

# 4. Analyze Buy Portfolio
BUY_CSV_CONTENT=""
if [ -f "$BUY_CSV" ]; then
    BUY_CSV_CONTENT=$(cat "$BUY_CSV")
fi

# 5. Check App Status
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R -s '.'),
    "sell_csv_content": $(echo "$SELL_CSV_CONTENT" | jq -R -s '.'),
    "buy_csv_content": $(echo "$BUY_CSV_CONTENT" | jq -R -s '.'),
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
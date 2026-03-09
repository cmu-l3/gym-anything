#!/bin/bash
set -e

echo "=== Exporting Liquidate Portfolio Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather Paths and Times
PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio"
BUY_CSV="$PORTFOLIO_DIR/buyportfolio.csv"
SELL_CSV="$PORTFOLIO_DIR/sellportfolio.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check File Timestamps (Anti-gaming)
SELL_MODIFIED="false"
if [ -f "$SELL_CSV" ]; then
    SELL_MTIME=$(stat -c %Y "$SELL_CSV" 2>/dev/null || echo "0")
    if [ "$SELL_MTIME" -gt "$TASK_START" ]; then
        SELL_MODIFIED="true"
    fi
fi

# 4. Check App State
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 5. Prepare Files for Verifier
# We copy the actual CSVs to /tmp so the verifier can parse them with Python
# This is more robust than trying to parse CSV with bash
cp "$BUY_CSV" /tmp/buyportfolio_result.csv 2>/dev/null || touch /tmp/buyportfolio_result.csv
cp "$SELL_CSV" /tmp/sellportfolio_result.csv 2>/dev/null || touch /tmp/sellportfolio_result.csv
chmod 666 /tmp/buyportfolio_result.csv /tmp/sellportfolio_result.csv

# 6. Create Result JSON
# Contains metadata and status flags
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sell_file_exists": $([ -f "$SELL_CSV" ] && echo "true" || echo "false"),
    "sell_file_modified": $SELL_MODIFIED,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "buy_csv_path": "/tmp/buyportfolio_result.csv",
    "sell_csv_path": "/tmp/sellportfolio_result.csv"
}
EOF

# 7. Safe Move to Output
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result at /tmp/task_result.json"
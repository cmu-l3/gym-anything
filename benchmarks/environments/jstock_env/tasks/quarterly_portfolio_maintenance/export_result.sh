#!/bin/bash
echo "=== Exporting quarterly_portfolio_maintenance results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# JStock Data Paths
PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio"
DEPOSIT_FILE="$PORTFOLIO_DIR/depositsummary.csv"
BUY_FILE="$PORTFOLIO_DIR/buyportfolio.csv"
EXPORT_FILE="/home/ga/Documents/Q1_2024_Portfolio_Report.csv"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if App was running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 3. Check Export File
EXPORT_EXISTS="false"
EXPORT_SIZE="0"
EXPORT_CREATED_DURING_TASK="false"

if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_FILE" 2>/dev/null || echo "0")
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
        EXPORT_CREATED_DURING_TASK="true"
    fi
fi

# 4. Stage internal data files for verifier
# We copy them to /tmp so the verifier can read them easily via copy_from_env
# We rename them to avoid confusion
cp "$DEPOSIT_FILE" /tmp/verify_deposits.csv 2>/dev/null || echo "No deposits file"
cp "$BUY_FILE" /tmp/verify_buys.csv 2>/dev/null || echo "No buys file"
if [ "$EXPORT_EXISTS" == "true" ]; then
    cp "$EXPORT_FILE" /tmp/verify_export.csv
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "export_exists": $EXPORT_EXISTS,
    "export_created_during_task": $EXPORT_CREATED_DURING_TASK,
    "export_size_bytes": $EXPORT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "deposit_file_path": "/tmp/verify_deposits.csv",
    "buy_file_path": "/tmp/verify_buys.csv",
    "export_file_path": "/tmp/verify_export.csv"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
echo "=== Export complete ==="
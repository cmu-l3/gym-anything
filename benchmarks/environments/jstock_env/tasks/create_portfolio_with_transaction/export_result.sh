#!/bin/bash
echo "=== Exporting task results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# 2. Gracefully close JStock to ensure data is flushed to disk
# JStock usually saves immediately, but this is safer.
echo "Closing JStock to flush data..."
DISPLAY=:1 wmctrl -c "JStock" 2>/dev/null || true
sleep 3
# Force kill if still running
pkill -f "jstock.jar" 2>/dev/null || true

# 3. Gather Verification Data
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
JSTOCK_BASE="/home/ga/.jstock/1.0.7/UnitedState/portfolios"
TARGET_DIR="$JSTOCK_BASE/Retirement Fund"
DEFAULT_DIR="$JSTOCK_BASE/My Portfolio"
TARGET_CSV="$TARGET_DIR/buyportfolio.csv"

# Check if new portfolio directory exists
if [ -d "$TARGET_DIR" ]; then
    PORTFOLIO_EXISTS="true"
    # Check creation time of the directory (anti-gaming)
    DIR_CTIME=$(stat -c %Y "$TARGET_DIR" 2>/dev/null || echo "0")
else
    PORTFOLIO_EXISTS="false"
    DIR_CTIME="0"
fi

# Read content of the new portfolio CSV if it exists
if [ -f "$TARGET_CSV" ]; then
    CSV_CONTENT=$(cat "$TARGET_CSV" | base64 -w 0)
    CSV_MTIME=$(stat -c %Y "$TARGET_CSV" 2>/dev/null || echo "0")
else
    CSV_CONTENT=""
    CSV_MTIME="0"
fi

# Read content of the default portfolio (to ensure it wasn't overwritten)
if [ -f "$DEFAULT_DIR/buyportfolio.csv" ]; then
    DEFAULT_CONTENT=$(cat "$DEFAULT_DIR/buyportfolio.csv" | base64 -w 0)
else
    DEFAULT_CONTENT=""
fi

# 4. Create JSON Result
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "portfolio_exists": $PORTFOLIO_EXISTS,
    "portfolio_dir_ctime": $DIR_CTIME,
    "csv_content_b64": "$CSV_CONTENT",
    "csv_mtime": $CSV_MTIME,
    "default_portfolio_content_b64": "$DEFAULT_CONTENT",
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
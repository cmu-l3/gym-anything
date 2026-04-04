#!/bin/bash
echo "=== Exporting delete_portfolio_transaction results ==="

# Paths
PORTFOLIO_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check File Stats
FILE_EXISTS="false"
FILE_MODIFIED="false"
ROW_COUNT=0
CONTAINS_MSFT="false"
CONTAINS_AAPL="false"
CONTAINS_NVDA="false"

if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$PORTFOLIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi

    # Check content
    # Count rows (excluding header, so subtract 1, but handle empty case)
    TOTAL_LINES=$(wc -l < "$PORTFOLIO_FILE")
    if [ "$TOTAL_LINES" -gt 0 ]; then
        ROW_COUNT=$((TOTAL_LINES - 1))
    fi

    if grep -q "MSFT" "$PORTFOLIO_FILE" || grep -q "Microsoft Corp." "$PORTFOLIO_FILE"; then
        CONTAINS_MSFT="true"
    fi

    if grep -q "AAPL" "$PORTFOLIO_FILE"; then
        CONTAINS_AAPL="true"
    fi

    if grep -q "NVDA" "$PORTFOLIO_FILE"; then
        CONTAINS_NVDA="true"
    fi
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "row_count": $ROW_COUNT,
    "contains_msft": $CONTAINS_MSFT,
    "contains_aapl": $CONTAINS_AAPL,
    "contains_nvda": $CONTAINS_NVDA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive rights
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
#!/bin/bash
echo "=== Exporting Reconstruct Portfolio Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png" 2>/dev/null || true

# Define paths
PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/Recovery"
RESULT_JSON="/tmp/task_result.json"

# Check if portfolio directory exists
if [ -d "$PORTFOLIO_DIR" ]; then
    PORTFOLIO_EXISTS="true"
    
    # Check creation time of the directory (anti-gaming)
    DIR_CTIME=$(stat -c %Y "$PORTFOLIO_DIR" 2>/dev/null || echo "0")
    if [ "$DIR_CTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    PORTFOLIO_EXISTS="false"
    CREATED_DURING_TASK="false"
fi

# Function to read file content safely or return empty string
read_file_content() {
    local file="$1"
    if [ -f "$file" ]; then
        # Read file, escape double quotes and backslashes for JSON inclusion
        # Note: Using python for safer JSON escaping of file content
        python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))" < "$file"
    else
        echo '""'
    fi
}

# Read contents of the 4 key CSV files
# We wrap the content in Python's json.dumps to handle newlines/quotes correctly
CONTENT_BUY=$(read_file_content "$PORTFOLIO_DIR/buyportfolio.csv")
CONTENT_SELL=$(read_file_content "$PORTFOLIO_DIR/sellportfolio.csv")
CONTENT_DEPOSIT=$(read_file_content "$PORTFOLIO_DIR/depositsummary.csv")
CONTENT_DIVIDEND=$(read_file_content "$PORTFOLIO_DIR/dividendsummary.csv")

# Build JSON result
# using a temp file to avoid quoting hell in bash
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "portfolio_exists": $PORTFOLIO_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "files": {
        "buy_csv": $CONTENT_BUY,
        "sell_csv": $CONTENT_SELL,
        "deposit_csv": $CONTENT_DEPOSIT,
        "dividend_csv": $CONTENT_DIVIDEND
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
ls -l "$RESULT_JSON"
echo "=== Export complete ==="
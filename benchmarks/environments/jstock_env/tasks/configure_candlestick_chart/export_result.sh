#!/bin/bash
echo "=== Exporting configure_candlestick_chart result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ============================================================
# Check Configuration Files
# ============================================================
JSTOCK_DIR="/home/ga/.jstock/1.0.7"
CONFIG_MODIFIED="false"
FOUND_CANDLESTICK="false"
FOUND_VOLUME="false"
MODIFIED_FILES=""

# Find files modified during the task
# We look specifically in the .jstock directory
echo "Searching for modified config files..."
MODIFIED_FILES_LIST=$(find "$JSTOCK_DIR" -type f -newermt "@$TASK_START" 2>/dev/null)

if [ -n "$MODIFIED_FILES_LIST" ]; then
    CONFIG_MODIFIED="true"
    MODIFIED_FILES=$(echo "$MODIFIED_FILES_LIST" | tr '\n' ', ')
    
    # Grep for keywords in these modified files
    # "Candlestick" or type codes (often integer) and "Volume"
    # Note: exact XML keys vary by version, so we grep broadly
    
    # Check for Candlestick (case insensitive)
    if grep -ri "Candle" "$JSTOCK_DIR" 2>/dev/null; then
        FOUND_CANDLESTICK="true"
    fi
    
    # Check for Volume visibility
    if grep -ri "Volume" "$JSTOCK_DIR" 2>/dev/null; then
        FOUND_VOLUME="true"
    fi
fi

# ============================================================
# Generate Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_modified": $CONFIG_MODIFIED,
    "modified_files": "$MODIFIED_FILES",
    "found_candlestick_keyword": $FOUND_CANDLESTICK,
    "found_volume_keyword": $FOUND_VOLUME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to safe location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
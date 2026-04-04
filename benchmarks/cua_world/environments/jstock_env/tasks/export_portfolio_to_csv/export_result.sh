#!/bin/bash
echo "=== Exporting task results ==="

# 1. Capture basic info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/portfolio_export.csv"

# 2. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# 3. Analyze output file
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
HAS_HEADER="false"
HAS_AAPL="false"
HAS_MSFT="false"
HAS_NVDA="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Content checks (simple grep)
    # Check for common header terms: Code, Symbol, Units, Price
    if grep -Ei "Code|Symbol|Units|Price" "$OUTPUT_PATH" | head -n 5 > /dev/null; then
        HAS_HEADER="true"
    fi

    # Check for specific data
    if grep -q "AAPL" "$OUTPUT_PATH"; then HAS_AAPL="true"; fi
    if grep -q "MSFT" "$OUTPUT_PATH"; then HAS_MSFT="true"; fi
    if grep -q "NVDA" "$OUTPUT_PATH"; then HAS_NVDA="true"; fi
fi

# 4. Check if app is still running
APP_RUNNING="false"
if pgrep -f "jstock.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON result
# Using python to write JSON avoids escaping hell in bash
python3 -c "
import json
result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': $OUTPUT_EXISTS, # boolean literal in python matches true/false if lowercase, but we passed string. Fix below.
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'output_size_bytes': $OUTPUT_SIZE,
    'app_was_running': $APP_RUNNING,
    'has_header': $HAS_HEADER,
    'has_aapl': $HAS_AAPL,
    'has_msft': $HAS_MSFT,
    'has_nvda': $HAS_NVDA,
    'screenshot_path': '/tmp/task_final.png'
}
# Convert string booleans to real booleans for cleaner JSON if desired, or keep as is.
# Let's write it out.
print(json.dumps(result, indent=2))
" > /tmp/task_result_temp.json

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
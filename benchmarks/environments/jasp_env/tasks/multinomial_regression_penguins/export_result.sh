#!/bin/bash
echo "=== Exporting task results ==="

# Record timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

JASP_FILE="/home/ga/Documents/JASP/Penguin_Multinomial.jasp"
TEXT_FILE="/home/ga/Documents/JASP/model_performance.txt"

# 1. Check JASP file existence and timestamps
JASP_EXISTS="false"
JASP_CREATED_DURING_TASK="false"
JASP_ANALYSIS_CONTENT=""

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_MTIME=$(stat -c %Y "$JASP_FILE" 2>/dev/null || echo "0")
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING_TASK="true"
    fi
    
    # Attempt to extract analysis details from JASP file (it's a ZIP)
    # We look for files containing analysis specifications (often JSON)
    TEMP_UNZIP=$(mktemp -d)
    echo "Inspecting JASP file structure..."
    unzip -q "$JASP_FILE" -d "$TEMP_UNZIP" 2>/dev/null || true
    
    # Search for JSON files that might contain the analysis config
    # Commonly 'index.json', 'analyses.json', or embedded folder structure
    # We grab the first 50 lines of relevant JSONs to keep result size manageable
    JASP_ANALYSIS_CONTENT=$(grep -r "Multinomial" "$TEMP_UNZIP" | head -n 20 2>/dev/null || echo "")
    
    # Also just list the file structure to verify it's a valid archive
    ARCHIVE_LIST=$(unzip -l "$JASP_FILE" | head -n 10)
    
    rm -rf "$TEMP_UNZIP"
fi

# 2. Check Text file existence and content
TEXT_EXISTS="false"
TEXT_CONTENT=""
TEXT_CREATED_DURING_TASK="false"

if [ -f "$TEXT_FILE" ]; then
    TEXT_EXISTS="true"
    TEXT_CONTENT=$(cat "$TEXT_FILE" | head -n 1)
    TEXT_MTIME=$(stat -c %Y "$TEXT_FILE" 2>/dev/null || echo "0")
    if [ "$TEXT_MTIME" -gt "$TASK_START" ]; then
        TEXT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if JASP is running
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
# Use python to safely construct JSON with potentially messy content strings
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'jasp_file_exists': $JASP_EXISTS,
    'jasp_created_during_task': $JASP_CREATED_DURING_TASK,
    'text_file_exists': $TEXT_EXISTS,
    'text_content': '''$TEXT_CONTENT'''.strip(),
    'text_created_during_task': $TEXT_CREATED_DURING_TASK,
    'app_was_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png',
    'archive_listing': '''$ARCHIVE_LIST''',
    'jasp_analysis_snippet': '''$JASP_ANALYSIS_CONTENT'''
}
print(json.dumps(result))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
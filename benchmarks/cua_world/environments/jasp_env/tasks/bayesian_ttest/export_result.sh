#!/bin/bash
echo "=== Exporting Bayesian T-Test Results ==="

# Define paths
JASP_FILE="/home/ga/Documents/JASP/InvisibilityCloak_BayesianTTest.jasp"
TXT_FILE="/home/ga/Documents/JASP/bayesian_ttest_results.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# Helper for JSON bools
bool_str() {
    if [ "$1" = "true" ]; then echo "true"; else echo "false"; fi
}

# 1. Check JASP File
JASP_EXISTS="false"
JASP_CREATED_DURING_TASK="false"
JASP_SIZE=0

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c%s "$JASP_FILE")
    JASP_MTIME=$(stat -c%Y "$JASP_FILE")
    if [ "$JASP_MTIME" -ge "$TASK_START" ]; then
        JASP_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Text Results File
TXT_EXISTS="false"
TXT_CREATED_DURING_TASK="false"
TXT_CONTENT=""

if [ -f "$TXT_FILE" ]; then
    TXT_EXISTS="true"
    TXT_MTIME=$(stat -c%Y "$TXT_FILE")
    if [ "$TXT_MTIME" -ge "$TASK_START" ]; then
        TXT_CREATED_DURING_TASK="true"
    fi
    # Read content safely (escape quotes)
    TXT_CONTENT=$(cat "$TXT_FILE" | head -n 5 | sed 's/"/\\"/g' | tr '\n' ' || ')
fi

# 3. Check App Status
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 5. Create JSON Result
# Note: We rely on verifier.py to actually copy and parse the JASP file structure.
# This JSON provides metadata and basic existence checks.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $NOW,
    "jasp_file": {
        "exists": $(bool_str $JASP_EXISTS),
        "created_during_task": $(bool_str $JASP_CREATED_DURING_TASK),
        "size_bytes": $JASP_SIZE,
        "path": "$JASP_FILE"
    },
    "txt_file": {
        "exists": $(bool_str $TXT_EXISTS),
        "created_during_task": $(bool_str $TXT_CREATED_DURING_TASK),
        "content_preview": "$TXT_CONTENT",
        "path": "$TXT_FILE"
    },
    "app_running": $(bool_str $APP_RUNNING),
    "screenshot_exists": $(bool_str $SCREENSHOT_EXISTS)
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json
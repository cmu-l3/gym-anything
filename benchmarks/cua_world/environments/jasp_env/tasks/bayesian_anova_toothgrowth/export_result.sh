#!/bin/bash
echo "=== Exporting Bayesian ANOVA results ==="

# Define paths
JASP_OUTPUT="/home/ga/Documents/JASP/ToothGrowth_BayesianANOVA.jasp"
TEXT_OUTPUT="/home/ga/Documents/JASP/bayesian_anova_results.txt"
TASK_START_FILE="/tmp/task_start_time.txt"
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check JASP project file
JASP_EXISTS="false"
JASP_CREATED_DURING_TASK="false"
JASP_SIZE=0

if [ -f "$JASP_OUTPUT" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c%s "$JASP_OUTPUT")
    JASP_MTIME=$(stat -c%Y "$JASP_OUTPUT")
    
    if [ "$JASP_MTIME" -ge "$TASK_START" ]; then
        JASP_CREATED_DURING_TASK="true"
    fi
    
    # Copy to /tmp for verifier access
    cp "$JASP_OUTPUT" /tmp/output.jasp
    chmod 666 /tmp/output.jasp
fi

# 2. Check Text summary file
TEXT_EXISTS="false"
TEXT_CREATED_DURING_TASK="false"
TEXT_CONTENT=""

if [ -f "$TEXT_OUTPUT" ]; then
    TEXT_EXISTS="true"
    TEXT_MTIME=$(stat -c%Y "$TEXT_OUTPUT")
    
    if [ "$TEXT_MTIME" -ge "$TASK_START" ]; then
        TEXT_CREATED_DURING_TASK="true"
    fi
    
    # Read content (limit size just in case)
    TEXT_CONTENT=$(head -c 2000 "$TEXT_OUTPUT")
    
    # Copy to /tmp for verifier access
    cp "$TEXT_OUTPUT" /tmp/output.txt
    chmod 666 /tmp/output.txt
fi

# 3. Check if JASP is still running
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null || pgrep -f "JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file": {
        "exists": $JASP_EXISTS,
        "created_during_task": $JASP_CREATED_DURING_TASK,
        "size_bytes": $JASP_SIZE,
        "path": "$JASP_OUTPUT"
    },
    "text_file": {
        "exists": $TEXT_EXISTS,
        "created_during_task": $TEXT_CREATED_DURING_TASK,
        "path": "$TEXT_OUTPUT"
    },
    "app_running": $APP_RUNNING
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
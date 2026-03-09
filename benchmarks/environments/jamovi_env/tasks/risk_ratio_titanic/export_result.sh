#!/bin/bash
echo "=== Exporting Risk Ratio Titanic results ==="

# 1. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Check .omv file (Jamovi Project)
OMV_PATH="/home/ga/Documents/Jamovi/Titanic_Risk_Analysis.omv"
OMV_EXISTS="false"
OMV_CREATED_DURING="false"
OMV_SIZE=0

if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$OMV_PATH")
    OMV_MTIME=$(stat -c %Y "$OMV_PATH")
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING="true"
    fi
fi

# 4. Check .txt file (Reported Value)
TXT_PATH="/home/ga/Documents/Jamovi/risk_value.txt"
TXT_EXISTS="false"
TXT_CONTENT=""

if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
    # Read first line, trim whitespace
    TXT_CONTENT=$(head -n 1 "$TXT_PATH" | tr -d '[:space:]')
fi

# 5. Check if Jamovi is running
APP_RUNNING="false"
if pgrep -f "org.jamovi.jamovi" > /dev/null || pgrep -f "jamovi" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING,
    "omv_size_bytes": $OMV_SIZE,
    "txt_exists": $TXT_EXISTS,
    "txt_content": "$TXT_CONTENT",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "omv_path_internal": "$OMV_PATH"
}
EOF

# 7. Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# 8. Copy the OMV file to temp for the verifier to access via copy_from_env
if [ "$OMV_EXISTS" == "true" ]; then
    cp "$OMV_PATH" /tmp/analysis_result.omv
    chmod 666 /tmp/analysis_result.omv
fi

echo "=== Export complete ==="
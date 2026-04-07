#!/bin/bash
echo "=== Exporting 3D Asset Pipeline Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

WORKSPACE_DIR="/home/ga/workspace/asset_pipeline"
RESULT_FILE="/tmp/asset_pipeline_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus VSCode and save
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key ctrl+s" 2>/dev/null || true
sleep 1

# Check if script was modified
SCRIPT_MODIFIED="false"
if [ -f "$WORKSPACE_DIR/process_models.py" ]; then
    SCRIPT_MTIME=$(stat -c %Y "$WORKSPACE_DIR/process_models.py" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    # Read the script content
    SCRIPT_CONTENT=$(cat "$WORKSPACE_DIR/process_models.py" | base64 -w 0)
else
    SCRIPT_CONTENT=""
fi

# Run the agent's script against the HIDDEN evaluation set to prevent gaming
echo "Running agent script on hidden evaluation set..."

# Swap test_models with hidden_models temporarily
mv "$WORKSPACE_DIR/data/test_models" "$WORKSPACE_DIR/data/visible_models" 2>/dev/null || true
cp -r /var/lib/asset_pipeline/hidden_models "$WORKSPACE_DIR/data/test_models"

# Execute
cd "$WORKSPACE_DIR"
EXEC_ERROR=""
sudo -u ga timeout 10 python3 process_models.py > /tmp/hidden_run.log 2>&1
EXEC_EXIT_CODE=$?

if [ $EXEC_EXIT_CODE -ne 0 ]; then
    EXEC_ERROR=$(cat /tmp/hidden_run.log | tail -n 10 | base64 -w 0)
fi

# Read output JSON if generated
JSON_CONTENT=""
if [ -f "assets.json" ]; then
    JSON_CONTENT=$(cat assets.json | base64 -w 0)
fi

# Restore workspace
rm -rf "$WORKSPACE_DIR/data/test_models"
mv "$WORKSPACE_DIR/data/visible_models" "$WORKSPACE_DIR/data/test_models" 2>/dev/null || true
rm -f "$WORKSPACE_DIR/assets.json" 2>/dev/null || true

# Build export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_modified": $SCRIPT_MODIFIED,
    "exec_exit_code": $EXEC_EXIT_CODE,
    "exec_error_b64": "$EXEC_ERROR",
    "script_content_b64": "$SCRIPT_CONTENT",
    "output_json_b64": "$JSON_CONTENT"
}
EOF

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE"
rm -f "$TEMP_JSON"

echo "Export complete: $RESULT_FILE"
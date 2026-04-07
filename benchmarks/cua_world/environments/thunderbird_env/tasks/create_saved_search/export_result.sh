#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROFILE_DIR="/home/ga/.thunderbird/default-release"
VF_PATH="${PROFILE_DIR}/virtualFolders.dat"

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check virtualFolders.dat
VF_EXISTS="false"
VF_MTIME="0"
VF_SIZE="0"

if [ -f "$VF_PATH" ]; then
    VF_EXISTS="true"
    VF_MTIME=$(stat -c %Y "$VF_PATH" 2>/dev/null || echo "0")
    VF_SIZE=$(stat -c %s "$VF_PATH" 2>/dev/null || echo "0")
    
    # Copy to /tmp/ so it's easily retrieved by the verifier without path/permission issues
    cp "$VF_PATH" /tmp/virtualFolders.dat
    chmod 666 /tmp/virtualFolders.dat
else
    # Create an empty file to prevent copy_from_env failures
    touch /tmp/virtualFolders.dat
    chmod 666 /tmp/virtualFolders.dat
fi

# Check if application is running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "vf_exists": $VF_EXISTS,
    "vf_mtime": $VF_MTIME,
    "vf_size_bytes": $VF_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
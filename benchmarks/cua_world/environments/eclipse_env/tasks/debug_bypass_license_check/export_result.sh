#!/bin/bash
echo "=== Exporting debug_bypass_license_check result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_SRC_DIR="/home/ga/Downloads/EnterpriseServer/src/main/java/com/enterprise/server"
# Also check workspace dir in case they imported and copied
WORKSPACE_SRC_DIR="/home/ga/eclipse-workspace/EnterpriseServer/src/main/java/com/enterprise/server"

# 1. Check for success log file
# The log file might be in Downloads/EnterpriseServer or eclipse-workspace/EnterpriseServer
# depending on how they imported/ran it.
LOG_FILE_NAME="startup_success.log"
LOG_FOUND="false"
LOG_CONTENT=""
LOG_PATH=""

find_log_file() {
    find /home/ga -name "$LOG_FILE_NAME" -type f -not -path "*/.*" 2>/dev/null | head -n 1
}

LOG_PATH=$(find_log_file)

if [ -n "$LOG_PATH" ]; then
    LOG_FOUND="true"
    LOG_CONTENT=$(cat "$LOG_PATH" | head -n 1)
    
    # Check timestamp of log file
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
    if [ "$LOG_MTIME" -gt "$TASK_START" ]; then
        LOG_CREATED_DURING_TASK="true"
    else
        LOG_CREATED_DURING_TASK="false"
    fi
else
    LOG_CREATED_DURING_TASK="false"
fi

# 2. Check Code Integrity (LicenseManager.java)
# We need to find where the agent is working.
TARGET_JAVA_FILE=""
if [ -f "$WORKSPACE_SRC_DIR/LicenseManager.java" ]; then
    TARGET_JAVA_FILE="$WORKSPACE_SRC_DIR/LicenseManager.java"
elif [ -f "$PROJECT_SRC_DIR/LicenseManager.java" ]; then
    TARGET_JAVA_FILE="$PROJECT_SRC_DIR/LicenseManager.java"
fi

ORIGINAL_HASH=$(cat /tmp/license_manager_original_hash.txt 2>/dev/null || echo "unknown")
CURRENT_HASH=""
CODE_MODIFIED="true" # Assume modified/fail if file missing

if [ -f "$TARGET_JAVA_FILE" ]; then
    CURRENT_HASH=$(md5sum "$TARGET_JAVA_FILE" | awk '{print $1}')
    if [ "$CURRENT_HASH" == "$ORIGINAL_HASH" ]; then
        CODE_MODIFIED="false"
    fi
fi

# 3. Check for Debug Perspective Evidence (Screenshot/Window Title)
# This is largely handled by VLM, but we can check window title for "Debug"
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l | grep -i "eclipse" | head -1)
DEBUG_PERSPECTIVE_OPEN="false"
if echo "$WINDOW_TITLE" | grep -qi "Debug"; then
    DEBUG_PERSPECTIVE_OPEN="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "log_found": $LOG_FOUND,
    "log_content": "$(echo "$LOG_CONTENT" | sed 's/"/\\"/g')",
    "log_created_during_task": $LOG_CREATED_DURING_TASK,
    "original_hash": "$ORIGINAL_HASH",
    "current_hash": "$CURRENT_HASH",
    "code_modified": $CODE_MODIFIED,
    "debug_perspective_active": $DEBUG_PERSPECTIVE_OPEN,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
#!/bin/bash
echo "=== Exporting create_new_user_profile results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_USER="Subject_Alpha"
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"

# 1. CHECK FOR PROFILE ARTIFACTS
# OpenBCI GUI v5 creates a folder in Settings/Users/<Name> OR updates Settings/User_Settings.json
PROFILE_FOUND="false"
PROFILE_PATH=""

# Check method A: Directory existence
if [ -d "$SETTINGS_DIR/Users/$TARGET_USER" ]; then
    PROFILE_FOUND="true"
    PROFILE_PATH="$SETTINGS_DIR/Users/$TARGET_USER"
    echo "Found profile directory: $PROFILE_PATH"
fi

# Check method B: Settings file entry (backup check)
SETTINGS_FILE="$SETTINGS_DIR/User_Settings.json"
SETTINGS_CONTAINS_USER="false"
if [ -f "$SETTINGS_FILE" ]; then
    if grep -q "$TARGET_USER" "$SETTINGS_FILE"; then
        SETTINGS_CONTAINS_USER="true"
        # If directory check failed but json has it, we count it as created (maybe verifying just after creation)
        if [ "$PROFILE_FOUND" = "false" ]; then
             PROFILE_FOUND="true"
             PROFILE_PATH="User_Settings.json entry"
        fi
        echo "Found user in User_Settings.json"
    fi
fi

# Check timestamps of created artifacts
ARTIFACT_CREATED_DURING_TASK="false"
if [ -d "$SETTINGS_DIR/Users/$TARGET_USER" ]; then
    DIR_MTIME=$(stat -c %Y "$SETTINGS_DIR/Users/$TARGET_USER" 2>/dev/null || echo "0")
    if [ "$DIR_MTIME" -gt "$TASK_START" ]; then
        ARTIFACT_CREATED_DURING_TASK="true"
    fi
elif [ "$SETTINGS_CONTAINS_USER" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$SETTINGS_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        ARTIFACT_CREATED_DURING_TASK="true"
    fi
fi

# 2. CHECK APP STATE
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# 3. CAPTURE EVIDENCE
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. CREATE RESULT JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "profile_found": $PROFILE_FOUND,
    "profile_name_match": $([ "$PROFILE_FOUND" = "true" ] && echo "true" || echo "false"),
    "artifact_created_during_task": $ARTIFACT_CREATED_DURING_TASK,
    "settings_contains_user": $SETTINGS_CONTAINS_USER,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
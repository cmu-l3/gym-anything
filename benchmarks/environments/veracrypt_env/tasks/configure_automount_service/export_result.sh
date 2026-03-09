#!/bin/bash
echo "=== Exporting Configure Automount Service Result ==="

source /workspace/scripts/task_utils.sh

SERVICE_PATH="/etc/systemd/system/veracrypt-media.service"
MOUNT_POINT="/mnt/media_vault"
DATA_FILE="$MOUNT_POINT/catalog.csv"

# 1. Check Service File
SERVICE_EXISTS="false"
HAS_EXEC_START="false"
HAS_EXEC_STOP="false"
SERVICE_CONTENT=""

if [ -f "$SERVICE_PATH" ]; then
    SERVICE_EXISTS="true"
    # Read content safely
    SERVICE_CONTENT=$(cat "$SERVICE_PATH" | base64 -w 0)
    
    if grep -q "ExecStart" "$SERVICE_PATH"; then
        HAS_EXEC_START="true"
    fi
    if grep -q "ExecStop" "$SERVICE_PATH"; then
        HAS_EXEC_STOP="true"
    fi
fi

# 2. Check Service Status
SERVICE_ACTIVE="false"
SERVICE_ENABLED="false"

if systemctl is-active --quiet veracrypt-media.service; then
    SERVICE_ACTIVE="true"
fi
if systemctl is-enabled --quiet veracrypt-media.service; then
    SERVICE_ENABLED="true"
fi

# 3. Check Mount Status
VOLUME_MOUNTED="false"
if mountpoint -q "$MOUNT_POINT"; then
    VOLUME_MOUNTED="true"
fi

# 4. Check Data Accessibility
DATA_ACCESSIBLE="false"
DATA_CONTENT_snippet=""

if [ "$VOLUME_MOUNTED" = "true" ] && [ -f "$DATA_FILE" ]; then
    # Try to read the file
    if head -n 1 "$DATA_FILE" | grep -q "ID,Title"; then
        DATA_ACCESSIBLE="true"
        DATA_CONTENT_snippet=$(head -n 2 "$DATA_FILE" | base64 -w 0)
    fi
fi

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "service_exists": $SERVICE_EXISTS,
    "service_active": $SERVICE_ACTIVE,
    "service_enabled": $SERVICE_ENABLED,
    "has_exec_start": $HAS_EXEC_START,
    "has_exec_stop": $HAS_EXEC_STOP,
    "volume_mounted": $VOLUME_MOUNTED,
    "data_accessible": $DATA_ACCESSIBLE,
    "service_content_b64": "$SERVICE_CONTENT",
    "data_snippet_b64": "$DATA_CONTENT_snippet",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="
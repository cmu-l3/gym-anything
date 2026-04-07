#!/bin/bash
echo "=== Exporting Configure Database Connection Result ==="

# Source utilities if available, else define minimal needed
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
WINE_PREFIX="/home/ga/.wine"
MANAGER_BIN="$WINE_PREFIX/drive_c/MedinTux-2.16/Programmes/Manager/bin"
INI_FILE="$MANAGER_BIN/Manager.ini"
BACKUP_FILE="$MANAGER_BIN/Manager.ini.bak"

# 1. Check Manager.ini status
INI_EXISTS="false"
INI_MTIME="0"
INI_CONTENT_BASE64=""
HOST_VALUE=""
PORT_VALUE=""

if [ -f "$INI_FILE" ]; then
    INI_EXISTS="true"
    INI_MTIME=$(stat -c %Y "$INI_FILE" 2>/dev/null || echo "0")
    
    # Read content safely encoded
    INI_CONTENT_BASE64=$(base64 -w 0 "$INI_FILE")
    
    # Simple grep extraction for quick debug logging (verification does full parse)
    HOST_VALUE=$(grep -i "host" "$INI_FILE" | head -1 | cut -d'=' -f2 | tr -d ' \r\n')
    PORT_VALUE=$(grep -i "port" "$INI_FILE" | head -1 | cut -d'=' -f2 | tr -d ' \r\n')
fi

# 2. Check Backup status
BACKUP_EXISTS="false"
BACKUP_HASH=""
ORIGINAL_HASH=$(cat /tmp/original_ini_hash.txt 2>/dev/null || echo "")

if [ -f "$BACKUP_FILE" ]; then
    BACKUP_EXISTS="true"
    BACKUP_HASH=$(sha256sum "$BACKUP_FILE" | awk '{print $1}')
fi

# 3. Check modification timing
FILE_MODIFIED_DURING_TASK="false"
if [ "$INI_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED_DURING_TASK="true"
fi

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "ini_exists": $INI_EXISTS,
    "ini_path": "$INI_FILE",
    "ini_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "ini_content_base64": "$INI_CONTENT_BASE64",
    "extracted_host": "$HOST_VALUE",
    "extracted_port": "$PORT_VALUE",
    "backup_exists": $BACKUP_EXISTS,
    "backup_path": "$BACKUP_FILE",
    "backup_hash": "$BACKUP_HASH",
    "original_hash": "$ORIGINAL_HASH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
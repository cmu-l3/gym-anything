#!/bin/bash
echo "=== Exporting recover_deleted_camera results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check if "Server Room Camera" exists and get details
TARGET_NAME="Server Room Camera"
CAMERA_INFO=$(get_camera_by_name "$TARGET_NAME")

CAMERA_FOUND="false"
CAMERA_ONLINE="false"
RECORDING_ENABLED="false"
FPS_SETTING="0"
CAMERA_ID=""

if [ -n "$CAMERA_INFO" ] && [ "$CAMERA_INFO" != "null" ]; then
    CAMERA_FOUND="true"
    
    # Parse status and ID
    CAMERA_ID=$(echo "$CAMERA_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
    # Status is often in a separate runtime query, but 'status' field might be in resource object or need separate call
    # API: GET /rest/v1/devices/{id}/status usually needed, or it's in the list
    # Let's check the list object "status" field if present, otherwise assume online if found (simpler for export)
    # Actually, we should check if status is "Online".
    STATUS=$(echo "$CAMERA_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','Offline'))")
    if [ "$STATUS" = "Online" ]; then
        CAMERA_ONLINE="true"
    fi
    
    # Check recording schedule
    # "schedule": { "isEnabled": true, "tasks": [...] }
    IS_REC_ENABLED=$(echo "$CAMERA_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('schedule',{}).get('isEnabled', False)).lower())")
    if [ "$IS_REC_ENABLED" = "true" ]; then
        RECORDING_ENABLED="true"
        
        # Check FPS of first task
        FPS_SETTING=$(echo "$CAMERA_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); tasks=d.get('schedule',{}).get('tasks',[]); print(tasks[0].get('fps',0) if tasks else 0)")
    fi
fi

# 2. Check if inventory file was opened/read (Anti-gaming check)
# We check access time
INVENTORY_FILE="/home/ga/Documents/network_inventory.txt"
FILE_ACCESSED="false"
if [ -f "$INVENTORY_FILE" ]; then
    ACCESS_TIME=$(stat -c %X "$INVENTORY_FILE")
    if [ "$ACCESS_TIME" -gt "$TASK_START" ]; then
        FILE_ACCESSED="true"
    fi
fi

# 3. Export JSON
cat > /tmp/task_result.json << EOF
{
    "camera_found": $CAMERA_FOUND,
    "camera_name": "$TARGET_NAME",
    "camera_id": "$CAMERA_ID",
    "camera_online": $CAMERA_ONLINE,
    "recording_enabled": $RECORDING_ENABLED,
    "recording_fps": $FPS_SETTING,
    "inventory_file_accessed": $FILE_ACCESSED,
    "timestamp": $TASK_END
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete:"
cat /tmp/task_result.json
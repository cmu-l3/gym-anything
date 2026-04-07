#!/bin/bash
# Do NOT use set -e
echo "=== Exporting terminal_system_inventory task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/terminal_task_end.png" 2>/dev/null || true

REPORT_FILE="/home/ga/Documents/system_inventory.txt"
TASK_START=$(cat /tmp/terminal_system_inventory_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$REPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    # Copy to /tmp to make it easily accessible for the verifier
    cp "$REPORT_FILE" /tmp/system_inventory.txt
    chmod 666 /tmp/system_inventory.txt
fi

# Read ground truth (trimming quotes and newlines)
GT_KERNEL=$(cat /tmp/gt_kernel.txt | tr -d '\n')
GT_NICK=$(cat /tmp/gt_nick.txt | tr -d "'" | tr -d '"' | tr -d '\n')
GT_COLOR=$(cat /tmp/gt_color.txt | tr -d "'" | tr -d '"' | tr -d '\n')

# Create JSON using python to safely encode lists
python3 << PYEOF > /tmp/terminal_system_inventory_result.json
import json

result = {
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "gt_kernel": "$GT_KERNEL",
    "gt_nick": "$GT_NICK",
    "gt_color": "$GT_COLOR",
    "gt_activities": []
}

try:
    with open('/tmp/gt_activities.txt', 'r') as f:
        activities = [line.strip() for line in f.readlines() if line.strip()]
        result["gt_activities"] = activities
except Exception:
    pass

with open('/tmp/terminal_system_inventory_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/terminal_system_inventory_result.json
echo "Result saved to /tmp/terminal_system_inventory_result.json"
cat /tmp/terminal_system_inventory_result.json
echo "=== Export complete ==="
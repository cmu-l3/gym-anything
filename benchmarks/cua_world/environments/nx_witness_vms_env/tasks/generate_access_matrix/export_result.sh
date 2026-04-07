#!/bin/bash
echo "=== Exporting Access Matrix Report Result ==="

source /workspace/scripts/task_utils.sh

# Timestamp Check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/access_matrix_report.json"

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_PATH")
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Capture Final System State (Ground Truth)
# We dump the current state of API so verifier can compare against it
NX_TOKEN=$(cat "${NX_TOKEN_FILE}" 2>/dev/null || refresh_nx_token)

echo "Dumping system state for verification..."
# Dump Users
curl -sk -H "Authorization: Bearer ${NX_TOKEN}" "${NX_BASE}/rest/v1/users" > /tmp/ground_truth_users.json
# Dump Layouts
curl -sk -H "Authorization: Bearer ${NX_TOKEN}" "${NX_BASE}/rest/v1/layouts" > /tmp/ground_truth_layouts.json
# Dump Devices
curl -sk -H "Authorization: Bearer ${NX_TOKEN}" "${NX_BASE}/rest/v1/devices" > /tmp/ground_truth_devices.json
# Dump System Info
curl -sk "${NX_BASE}/rest/v1/system/info" > /tmp/ground_truth_system.json

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "task_start_time": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
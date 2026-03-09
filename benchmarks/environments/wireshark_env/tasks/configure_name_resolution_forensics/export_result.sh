#!/bin/bash
echo "=== Exporting configure_name_resolution_forensics results ==="

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ------------------------------------------------------------------
# GATHER DATA
# ------------------------------------------------------------------

# 1. Check Hosts File (User Config)
HOSTS_FILE="/home/ga/.config/wireshark/hosts"
HOSTS_CONTENT=""
HOSTS_EXISTS="false"
if [ -f "$HOSTS_FILE" ]; then
    HOSTS_EXISTS="true"
    HOSTS_CONTENT=$(cat "$HOSTS_FILE")
fi

# 2. Check System Hosts (Fallback, though less likely/desirable)
SYS_HOSTS_CONTENT=""
if [ -f "/etc/hosts" ]; then
    SYS_HOSTS_CONTENT=$(cat "/etc/hosts")
fi

# 3. Check Exported File
EXPORT_FILE="/home/ga/Documents/captures/smtp_resolved.txt"
EXPORT_EXISTS="false"
EXPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_CONTENT=$(head -n 50 "$EXPORT_FILE") # First 50 lines is enough
    
    # Check creation time
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Get Ground Truth (created in setup)
GT_SERVER_IP=$(python3 -c "import json; print(json.load(open('/tmp/ground_truth_ips.json')).get('server_ip', ''))" 2>/dev/null || echo "")
GT_CLIENT_IP=$(python3 -c "import json; print(json.load(open('/tmp/ground_truth_ips.json')).get('client_ip', ''))" 2>/dev/null || echo "")

# ------------------------------------------------------------------
# PACK INTO JSON
# ------------------------------------------------------------------
# Use python to safely escape strings for JSON
python3 -c "
import json
import sys

data = {
    'hosts_exists': '$HOSTS_EXISTS' == 'true',
    'hosts_content': sys.argv[1],
    'sys_hosts_content': sys.argv[2],
    'export_exists': '$EXPORT_EXISTS' == 'true',
    'export_content': sys.argv[3],
    'file_created_during_task': '$FILE_CREATED_DURING_TASK' == 'true',
    'gt_server_ip': '$GT_SERVER_IP',
    'gt_client_ip': '$GT_CLIENT_IP',
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
" "$HOSTS_CONTENT" "$SYS_HOSTS_CONTENT" "$EXPORT_CONTENT"

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
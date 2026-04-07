#!/bin/bash
set -e
echo "=== Exporting tune_storage_performance results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Refresh token to ensure we can query
refresh_nx_token > /dev/null 2>&1 || true
TOKEN=$(get_nx_token)
SERVER_ID=$(cat /tmp/nx_server_id.txt 2>/dev/null || get_server_id)

echo "Collecting final system state..."

# 1. Fetch System Settings (for Backup Bandwidth)
# Note: API field is typically 'maxBackupBandwidthBps' or similar in system settings
SYSTEM_SETTINGS=$(nx_api_get "/rest/v1/system/settings")

# 2. Fetch Storage Settings (for Reserved Space)
if [ -n "$SERVER_ID" ]; then
    STORAGE_SETTINGS=$(nx_api_get "/rest/v1/servers/${SERVER_ID}/storages")
else
    STORAGE_SETTINGS="[]"
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
# We use python to parse the API responses and construct a clean result object
python3 -c "
import json
import os
import sys

try:
    # Load raw API responses
    sys_settings_str = '''$SYSTEM_SETTINGS'''
    storage_settings_str = '''$STORAGE_SETTINGS'''
    
    sys_settings = json.loads(sys_settings_str) if sys_settings_str.strip() else {}
    storages = json.loads(storage_settings_str) if storage_settings_str.strip() else []
    
    # Extract Backup Bandwidth
    # Look for likely keys
    backup_bps = sys_settings.get('maxBackupBandwidthBps', -1)
    
    # Extract Storage Reserve
    # We look for ANY storage that has the target ~30GB, or just report the first/main one
    max_reserved = -1
    storage_id = None
    
    for s in storages:
        # Check if storage is active/online if possible, but mainly check the value
        r = s.get('reservedSpaceBytes', 0)
        if r > max_reserved:
            max_reserved = r
            storage_id = s.get('id')
            
    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'final_backup_bandwidth_bps': backup_bps,
        'final_reserved_space_bytes': max_reserved,
        'storage_id': storage_id,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    print(json.dumps(result, indent=2))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))

" > /tmp/task_result.json

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json
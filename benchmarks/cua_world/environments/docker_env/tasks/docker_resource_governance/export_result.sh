#!/bin/bash
echo "=== Exporting Docker Resource Governance Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Inspect Containers
# We capture the full JSON array of the 3 specific containers
INSPECT_JSON=$(docker inspect acme-api acme-worker acme-cache 2>/dev/null || echo "[]")

# 2. Check for Documentation
DOC_PATH="/home/ga/Desktop/resource_governance.md"
DOC_EXISTS="false"
DOC_CONTENT=""
if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_MTIME=$(stat -c %Y "$DOC_PATH" 2>/dev/null || echo "0")
    if [ "$DOC_MTIME" -gt "$TASK_START" ]; then
        DOC_CREATED_DURING_TASK="true"
    else
        DOC_CREATED_DURING_TASK="false"
    fi
    # Read content (limit size)
    DOC_CONTENT=$(head -c 5000 "$DOC_PATH")
else
    DOC_CREATED_DURING_TASK="false"
fi

# 3. Check OOM/Restart evidence for acme-worker specifically
# We look at RestartCount and OOMKilled flag
WORKER_RESTART_COUNT=$(docker inspect acme-worker --format '{{.RestartCount}}' 2>/dev/null || echo "0")
WORKER_OOM_KILLED=$(docker inspect acme-worker --format '{{.State.OOMKilled}}' 2>/dev/null || echo "false")

# 4. Construct Result JSON
# Using python to safely construct JSON to handle potentially messy doc content
python3 -c "
import json
import os
import sys

try:
    inspect_data = json.loads(os.environ.get('INSPECT_JSON', '[]'))
except:
    inspect_data = []

# Map container info by name
containers = {}
for c in inspect_data:
    name = c.get('Name', '').strip('/')
    containers[name] = {
        'Status': c.get('State', {}).get('Status', 'unknown'),
        'Memory': c.get('HostConfig', {}).get('Memory', 0),
        'NanoCpus': c.get('HostConfig', {}).get('NanoCpus', 0),
        'CpuQuota': c.get('HostConfig', {}).get('CpuQuota', 0),
        'CpuPeriod': c.get('HostConfig', {}).get('CpuPeriod', 0),
        'RestartPolicy': c.get('HostConfig', {}).get('RestartPolicy', {}).get('Name', ''),
        'RestartRetryCount': c.get('HostConfig', {}).get('RestartPolicy', {}).get('MaximumRetryCount', 0),
        'OOMKilled': c.get('State', {}).get('OOMKilled', False),
        'RestartCount': c.get('RestartCount', 0)
    }

result = {
    'task_start': int(os.environ.get('TASK_START', 0)),
    'containers': containers,
    'doc_exists': os.environ.get('DOC_EXISTS') == 'true',
    'doc_created_during_task': os.environ.get('DOC_CREATED_DURING_TASK') == 'true',
    'doc_content': os.environ.get('DOC_CONTENT', ''),
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
" 

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="
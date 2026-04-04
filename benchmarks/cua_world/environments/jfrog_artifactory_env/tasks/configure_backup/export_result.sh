#!/bin/bash
echo "=== Exporting configure_backup result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Fetch current system configuration
echo "Fetching final system configuration..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/system/configuration" > /tmp/final_config.xml

# Python script to parse the XML and extract backup details to JSON
# This runs inside the container to prepare a clean JSON for the verifier
python3 -c "
import sys
import json
import xml.etree.ElementTree as ET

try:
    tree = ET.parse('/tmp/final_config.xml')
    root = tree.getroot()
    
    backups = []
    # Namespaces might be involved, but usually Artifactory config is straightforward XML
    # We search specifically for the backup list
    
    # Handle optional namespace stripping if needed, or just find all 'backup' tags
    for backup in root.findall('.//backup'):
        key = backup.find('key')
        cron = backup.find('cronExp')
        retention = backup.find('retentionPeriodHours')
        enabled = backup.find('enabled')
        
        b_data = {
            'key': key.text if key is not None else None,
            'cronExp': cron.text if cron is not None else None,
            'retentionPeriodHours': int(retention.text) if retention is not None and retention.text.isdigit() else 0,
            'enabled': enabled.text.lower() == 'true' if enabled is not None else False
        }
        backups.append(b_data)

    result = {
        'backups': backups,
        'config_retrieved': True
    }
except Exception as e:
    result = {
        'backups': [],
        'config_retrieved': False,
        'error': str(e)
    }

print(json.dumps(result, indent=2))
" > /tmp/parsed_config.json

# Check if Firefox is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Prepare final result JSON
# We merge the parsed config into the final result
python3 -c "
import json
import os
import time

try:
    with open('/tmp/parsed_config.json', 'r') as f:
        config_data = json.load(f)
except:
    config_data = {'backups': [], 'config_retrieved': False}

task_start = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    pass

final_result = {
    'task_start': task_start,
    'task_end': int(time.time()),
    'app_was_running': '$APP_RUNNING' == 'true',
    'screenshot_path': '/tmp/task_final.png',
    'backups': config_data.get('backups', []),
    'config_retrieved': config_data.get('config_retrieved', False)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_result, f, indent=2)
"

# Set permissions to ensure verifier can read it
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="